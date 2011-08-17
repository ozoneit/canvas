#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class FoldersController < ApplicationController
  before_filter :require_context
  
  def index
    if authorized_action(@context, @current_user, :read)
      render :json => @folders.to_json(:methods => [:id, :currently_locked], :permissions => {:user => @current_user, :session => session})
    end
  end
  
  def show
    @folder = @context.folders.find(params[:id])
    if authorized_action(@folder, @current_user, :read_contents)
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_files_url, :folder_id => @folder.id) }
        files = if @context.grants_right?(@current_user, session, :manage_files)
                  @folder.active_file_attachments
                else
                  @folder.visible_file_attachments
                end
        res = {
          :actual_folder => @folder,
          :sub_folders => @folder.active_sub_folders,
          :files => files
        }
        format.json { render :json => res.to_json(:permissions => {:user => @current_user}, :methods => [:readable_size,:mime_class,:currently_locked]) }
      end
    end
  end
  
  def download
    if authorized_action(@context, @current_user, :read)
      @folder = @context.folders.find(params[:folder_id])
      user_id = @current_user && @current_user.id
      
      # Destroy any previous zip downloads that might exist for this folder, 
      # except the last one (cause we might be able to use it)
      @attachments = Attachment.find_all_by_context_id_and_context_type_and_display_name_and_user_id(@folder.id, @folder.class.to_s, "folder.zip", user_id).
                                select{|a| ['to_be_zipped', 'zipping', 'zipped'].include?(a.workflow_state) && !a.deleted? }.
                                sort_by{|a| a.created_at }
      @attachment = @attachments.pop
      @attachments.each{|a| a.destroy! }
      if @attachment && @attachment.created_at < @folder.active_file_attachments.map(&:updated_at).compact.max
        @attachment.destroy!
        @attachment = nil
      end
      
      if @attachment.nil?
        @attachment = @folder.file_attachments.build(:display_name => "folder.zip")
        @attachment.user_id = user_id
        @attachment.workflow_state = 'to_be_zipped'
        @attachment.file_state = '0'
        @attachment.context = @folder
        @attachment.save!
        ContentZipper.send_later_enqueue_args(:process_attachment, { :priority => Delayed::LOW_PRIORITY }, @attachment, @current_user)
        render :json => @attachment.to_json
      else
        respond_to do |format|
          if @attachment.zipped?
            format.json { render :json => @attachment.to_json(:methods => :readable_size) }
            if Attachment.s3_storage?
              format.html { redirect_to @attachment.cacheable_s3_url }
              format.zip { redirect_to @attachment.cacheable_s3_url }
            else
              format.html { send_file(@attachment.full_filename, :type => @attachment.content_type, :disposition => 'inline') }
              format.zip { send_file(@attachment.full_filename, :type => @attachment.content_type, :disposition => 'inline') }
            end
          else
            flash[:notice] = "File zipping still in process..."
            format.json { render :json => @attachment.to_json }
            format.html { redirect_to named_context_url(@context, :context_folder_url, @folder.id) }
            format.zip { redirect_to named_context_url(@context, :context_folder_url, @folder.id) }
          end
        end
      end
    end
  end
  
  def update
    @folder = @context.folders.find(params[:id])
    if authorized_action(@folder, @current_user, :update)
      respond_to do |format|
        just_hide = params[:folder].delete(:just_hide)
        if just_hide == '1'
          params[:folder][:locked] = false
          params[:folder][:hidden] = true
        end
        if parent_folder_id = params[:folder].delete(:parent_folder_id)
          params[:folder][:parent_folder] = @context.folders.active.find(parent_folder_id)
        end
        if @folder.update_attributes(params[:folder])
          if !@folder.parent_folder_id || !@context.folders.find_by_id(@folder)
            @folder.parent_folder = Folder.root_folders(@context).first
            @folder.save
          end
          flash[:notice] = 'Event was successfully updated.'
          format.html { redirect_to named_context_url(@context, :context_files_url) }
          format.xml  { head :ok }
          format.json { render :json => @folder.to_json(:methods => [:currently_locked], :permissions => {:user => @current_user, :session => session}), :status => :ok }
        else
          format.html { render :action => "edit" }
          format.xml  { render :xml => @folder.errors.to_xml }
          format.json { render :json => @folder.errors.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def create
    source_folder_id = params[:folder].delete(:source_folder_id)
    if parent_folder_id = params[:folder].delete(:parent_folder_id)
      parent_folder = @context.folders.find(parent_folder_id)
      params[:folder][:parent_folder] = parent_folder
    end

    @folder = @context.folders.build(params[:folder])
    if authorized_action(@folder, @current_user, :create)
      if !@folder.parent_folder_id || !@context.folders.find_by_id(@folder.parent_folder_id)
        @folder.parent_folder_id = Folder.unfiled_folder(@context).id
      end
      if source_folder_id && (source_folder = Folder.find_by_id(source_folder_id)) && source_folder.grants_right?(@current_user, session, :read)
        @folder = source_folder.clone_for(@context, @folder, {:everything => true})
      end
      respond_to do |format|
        if @folder.save
          flash[:notice] = 'Folder was successfully created.'
          format.html { redirect_to named_context_url(@context, :context_files_url) }
          format.xml  { head :created, @folder.to_xml }
          format.json { render :json => @folder.to_json(:permissions => {:user => @current_user, :session => session}) }
        else
          format.html { render :action => "new" }
          format.xml  { render :xml => @folder.errors.to_xml }
          format.json { render :json => @folder.errors.to_json }
        end
      end
    end
  end
  
  def destroy
    @folder = Folder.find(params[:id])
    if authorized_action(@folder, @current_user, :delete)
      @folder.destroy
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_files_url) }# show.rhtml
        format.xml  { render :xml => @folder.to_xml }
        format.json { render :json => @folder.to_json }
      end
    end
  end
end
