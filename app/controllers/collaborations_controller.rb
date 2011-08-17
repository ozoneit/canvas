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

class CollaborationsController < ApplicationController
  before_filter :require_context
  before_filter :require_collaborations_configured
  include GoogleDocs
  
  def require_collaborations_configured
    unless Collaboration.any_collaborations_configured?
      flash[:error] = "Collaborations have not been enabled for this Canvas site"
      redirect_to named_context_url(@context, :context_url)
      return false
    end
  end
  
  def index
    @collaborations = @context.collaborations.active
    if authorized_action(@context, @current_user, :read)
      return unless tab_enabled?(@context.class::TAB_COLLABORATIONS)
      log_asset_access("collaborations:#{@context.asset_string}", "collaborations", "other")
      @google_docs = google_doc_list rescue nil
      @users = @context.users
    end
  end
  
  def show
    @collaboration = @context.collaborations.find(params[:id])
    if authorized_action(@collaboration, @current_user, :read)
      @collaboration.touch
      if @collaboration.valid_user?(@current_user)
        @collaboration.authorize_user(@current_user)
        log_asset_access(@collaboration, "collaborations", "other")
        redirect_to @collaboration.url
      elsif @collaboration.is_a?(GoogleDocsCollaboration)
        redirect_to oauth_url(:service => :google_docs, :return_to => request.url)
      else
        flash[:error] = "Cannot load collaboration"
        redirect_to named_context_url(@context, :context_collaborations_url)
      end
    end
  end
  
  def create
    if authorized_action(@context.collaborations.new, @current_user, :create)
      collaborators = []#[@current_user]
      if params[:user]
        params[:user].each do |id, val|
          user = @context.users.find_by_id(id.to_i) if val == "1"
          collaborators << user if user
        end
      end
      collaborators.uniq!
      params[:collaboration][:user] = @current_user
      @collaboration = Collaboration.typed_collaboration_instance(params[:collaboration].delete(:collaboration_type))
      @collaboration.context = @context
      @collaboration.attributes = params[:collaboration]
      @collaboration.collaboration_users = collaborators unless collaborators.empty?
      respond_to do |format|
        if @collaboration.save
          format.html { redirect_to @collaboration.url }
          format.json { render :json => @collaboration.to_json(:methods => [:collaborator_ids], :permissions => {:user => @current_user, :session => session}) }
        else
          flash[:error] = "Collaboration creation failed"
          format.html { redirect_to named_context_url(@context, :context_collaborations_url) }
          forma.json { render :json => @collaboration.errors.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def update
    @collaboration = @context.collaborations.find(params[:id])
    if authorized_action(@collaboration, @current_user, :update)
      @collaboration
      collaborators = []#[@current_user]
      if params[:user]
        params[:user].each do |id, val|
          user = @context.users.find_by_id(id.to_i) if val == "1"
          collaborators << user if user
        end
      end
      collaborators.uniq!
      params[:collaboration].delete :collaboration_type
      @collaboration.attributes = params[:collaboration]
      @collaboration.collaboration_users = collaborators
      respond_to do |format|
        if @collaboration.save
          format.json { render :json => @collaboration.to_json(:methods => [:collaborator_ids], :permissions => {:user => @current_user, :session => session}) }
          format.html { redirect_to named_context_url(@context, :context_collaborations_url) }
        else
          flash[:error] = "Collaboration update failed"
          format.html { redirect_to named_context_url(@context, :context_collaborations_url) }
          format.json { render :json => @collaboration.errors.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def destroy
    @collaboration = @context.collaborations.find(params[:id])
    if authorized_action(@collaboration, @current_user, :delete)
      @collaboration.delete_document if params[:delete_doc]
      @collaboration.destroy
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :collaborations_url) }
        format.json { render :json => @collaboration.to_json }
      end
    end
  end
end

