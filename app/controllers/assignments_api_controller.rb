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

# @API Assignments
#
# API for accessing assignment information.
class AssignmentsApiController < ApplicationController
  before_filter :require_context

  include Api::V1::Assignment

  # @API
  # Returns the list of assignments for the current context.
  #
  # @response_field id The unique identifier for the assignment.
  # @response_field name The name of the assignment.
  # @response_field needs_grading_count [Integer] If the requesting user has grading rights, the number of submissions that need grading.
  # @response_field position [Integer] The sorting order of this assignment in
  #   the group.
  # @response_field points_possible The maximum possible points for the
  #   assignment.
  # @response_field grading_type [Optional, "pass_fail"|"percent"|"letter_grade"|"points"]
  #   The type of grade the assignment receives.
  # @response_field use_rubric_for_grading [Boolean] If true, the rubric is
  #   directly tied to grading the assignment. Otherwise, it is only advisory.
  # @response_field rubric [Rubric]
  #   A list of rows and ratings for each row. TODO: need more discussion of the
  #   rubric data format and usage for grading.
  #
  # @example_response
  #   [
  #     {
  #       "id": 4,
  #       "name": "some assignment",
  #       "points_possible": 12,
  #       "grading_type": "points",
  #       "submission_types" : [
  #         "online_upload",
  #         "online_text_entry",
  #         "online_url",
  #         "media_recording"
  #        ]
  #       "use_rubric_for_grading": true,
  #       "rubric": [
  #         {
  #           "ratings": [
  #             {
  #               "points": 10,
  #               "id": "rat1",
  #               "description": "A"
  #             },
  #             {
  #               "points": 7,
  #               "id": "rat2",
  #               "description": "B"
  #             },
  #             {
  #               "points": 0,
  #               "id": "rat3",
  #               "description": "F"
  #             }
  #           ],
  #           "points": 10,
  #           "id": "crit1",
  #           "description": "Crit1"
  #         },
  #         {
  #           "ratings": [
  #             {
  #               "points": 2,
  #               "id": "rat1",
  #               "description": "Pass"
  #             },
  #             {
  #               "points": 0,
  #               "id": "rat2",
  #               "description": "Fail"
  #             }
  #           ],
  #           "points": 2,
  #           "id": "crit2",
  #           "description": "Crit2"
  #         }
  #       ]
  #     }
  #   ]
  def index
    if authorized_action(@context, @current_user, :read)
      @assignments = @context.active_assignments.find(:all,
          :include => [:assignment_group, :rubric_association, :rubric],
          :order => 'assignment_groups.position, assignments.position')

      hashes = @assignments.map { |assignment|
        assignment_json(assignment, [], @context.user_is_teacher?(@current_user)) }

      render :json => hashes.to_json
    end
  end

  def show
    if authorized_action(@context, @current_user, :read)
      @assignment = @context.active_assignments.find(params[:id],
          :include => [:assignment_group, :rubric_association, :rubric])

      render :json => assignment_json(@assignment, [], @context.user_is_teacher?(@current_user)).to_json
    end
  end

  ALLOWED_FIELDS = %w(name position points_possible grading_type)

  # @API
  # Create a new assignment for this course. The assignment is created in the
  # active state.
  #
  # @argument assignment[name] The assignment name.
  # @argument assignment[position] [Integer] The position of this assignment in the
  #   group when displaying assignment lists.
  # @argument assignment[points_possible] [Float] The maximum points possible on
  #   the assignment.
  # @argument assignment[grading_type] [Optional, "pass_fail"|"percent"|"letter_grade"|"points"] The strategy used for grading the assignment. The assignment is ungraded if this field is omitted.
  def create
    assignment_params = {}
    if params[:assignment].is_a?(Hash)
      assignment_params = params[:assignment].slice(*ALLOWED_FIELDS)
    end
    # TODO: allow rubric creation

    @assignment = @context.active_assignments.build(assignment_params)

    if authorized_action(@assignment, @current_user, :create)
      if custom_vals = params[:assignment][:set_custom_field_values]
        @assignment.set_custom_field_values = custom_vals
      end

      if @assignment.save
        render :json => assignment_json(@assignment, [], @context.user_is_teacher?(@current_user)).to_json, :status => 201
      else
        # TODO: we don't really have a strategy in the API yet for returning
        # errors.
        render :json => 'error'.to_json, :status => 400
      end
    end
  end

  # @API
  # Modify an existing assignment. See the documentation for assignment
  # creation.
  def update
    assignment_params = {}
    if params[:assignment].is_a?(Hash)
      assignment_params = params[:assignment].slice(*ALLOWED_FIELDS)
    end

    @assignment = @context.assignments.find(params[:id])

    if authorized_action(@assignment, @current_user, :update_content)
      if custom_vals = params[:assignment][:set_custom_field_values]
        @assignment.set_custom_field_values = custom_vals
      end

      if @assignment.update_attributes(assignment_params)
        render :json => assignment_json(@assignment, [], @context.user_is_teacher?(@current_user)).to_json, :status => 201
      else
        # TODO: we don't really have a strategy in the API yet for returning
        # errors.
        render :json => 'error'.to_json, :status => 400
      end
    end
  end

end
