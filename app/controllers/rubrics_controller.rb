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

class RubricsController < ApplicationController
  before_filter :require_context
  before_filter { |c| c.active_tab = "rubrics" }

  def index
    if authorized_action(@context, @current_user, :manage)
      @rubric_associations = @context.rubric_associations.bookmarked.include_rubric.to_a
      @rubric_associations = @rubric_associations.select(&:rubric_id).once_per(&:rubric_id).sort_by{|a| a.rubric.title }
      @rubrics = @rubric_associations.map(&:rubric)
      if @context.is_a?(User)
        render :action => 'user_index'
      else
        render
      end
    end
  end
  
  def show
    if authorized_action(@context, @current_user, :manage)
      @rubric_association = @context.rubric_associations.bookmarked.find_by_rubric_id(params[:id])
      @actual_rubric = @rubric_association.rubric
    end
  end
  
  def assessments
    if authorized_action(@context, @current_user, :manage)
      @rubric_associations = @context.rubric_associations.bookmarked
      @rubrics = @rubric_associations.map{|r| r.rubric}
    end
  end
  
  def create
    @invitees = params[:rubric_association].delete(:invitations) rescue nil
    update
  end
  
  # This controller looks yucky (and is yucky) because it handles a funky logic.
  # If you try to update a rubric that is being used in more than one place,
  # instead of updating that rubric this will create a new rubric based on
  # the old rubric and return that one instead.  If you pass it a rubric_association_id
  # parameter, then it will point the rubric_association to the new rubric
  # instead of the old one.
  def update
    params[:rubric_association] ||= {}
    params[:rubric_association].delete(:invitations)
    @association_object = RubricAssociation.get_association_object(params[:rubric_association])
    params[:rubric][:user] = @current_user if params[:rubric]
    if (!@association_object || authorized_action(@association_object, @current_user, :read)) && authorized_action(@context, @current_user, :manage_grades)
      @association = @context.rubric_associations.find_by_id(params[:rubric_association_id])
      @association_object ||= @association.association if @association
      params[:rubric_association][:association] = @association_object
      params[:rubric_association][:update_if_existing] = params[:action] == 'update'
      @rubric = @association.rubric if params[:id] && @association && (@association.rubric_id == params[:id].to_i || (@association.rubric && @association.rubric.migration_id == "cloned_from_#{params[:id]}"))
      @rubric ||= @context.rubrics.find(params[:id]) if params[:id]
      @association = nil unless @association && @rubric && @association.rubric_id == @rubric.id
      params[:rubric_association][:id] = @association.id if @association
      # Update the rubric if you can
      # Better specify params[:rubric_association][:id] if you want it to update an existing association
      
      # If this is a brand new rubric OR if the rubric isn't editable,
      # then create a new rubric
      if !@rubric || (@rubric.will_change_with_update?(params[:rubric]) && !@rubric.grants_right?(@current_user, session, :update))
        original_rubric_id = @rubric && @rubric.id
        @rubric = @context.rubrics.build
        @rubric.rubric_id = original_rubric_id
        @rubric.user = @current_user
      end
      if params[:rubric] && (@rubric.grants_right?(@current_user, session, :update) || (@association && @association.grants_right?(@current_user, session, :update))) #authorized_action(@rubric, @current_user, :update)
        @association = @rubric.update_with_association(@current_user, params[:rubric], @context, params[:rubric_association], @invitees)
        @rubric = @association.rubric if @association
      end
      json_res = {
        :rubric => ActiveSupport::JSON.decode(@rubric.to_json(:methods => :criteria, :include_root => false, :permissions => {:user => @current_user, :session => session})),
        :rubric_association => ActiveSupport::JSON.decode(@association.to_json(:include_root => false, :include => [:rubric_assessments, :assessment_requests], :methods => :assessor_name, :permissions => {:user => @current_user, :session => session}))
      }
      render :json => json_res.to_json
    end
  end
  
  def destroy
    @rubric = @context.rubrics.find(params[:id])
    if authorized_action(@rubric, @current_user, :delete_associations)
      if @rubric.destroy_for(@context)
        render :json => @rubric.to_json
      else
        render :json => @rubric.errors.to_json, :status => :bad_request
      end
    end
  end

end
