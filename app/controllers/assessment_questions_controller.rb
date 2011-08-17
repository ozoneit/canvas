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

class AssessmentQuestionsController < ApplicationController
  before_filter :require_context
  def create
    if authorized_action(@context.assessment_questions.new, @current_user, :create)
      params[:assessment_question] ||= {}
      params[:assessment_question][:form_question_data] ||= params[:question]
      question_bank_id = params[:assessment_question].delete(:assessment_question_bank_id)
      @question = @context.assessment_questions.build(params[:assessment_question])
      if question_bank_id
        @bank = @context.assessment_question_banks.active.find_by_id(question_bank_id)
        @question.assessment_question_bank = @bank
      end
      if @question.save
        @question.insert_at_bottom
        render :json => @question.to_json
      else
        render :json => @question.errors.to_json, :status => :bad_request
      end
    end
  end
  
  def update
    @question = @context.assessment_questions.find(params[:id])
    if authorized_action(@question, @current_user, :update)
      params[:assessment_question] ||= {}
      # changing the question bank id needs to use the move action, below
      params[:assessment_question].delete(:assessment_question_bank_id)
      params[:assessment_question][:form_question_data] ||= params[:question]
      @question.edited_independent_of_quiz_question
      if @question.update_attributes(params[:assessment_question])
        @question.ensure_in_list
        render :json => @question.to_json
      else
        render :json => @question.errors.to_json, :status => :bad_request
      end
    end
  end
  
  def destroy
    @question = @context.assessment_questions.find(params[:id])
    if authorized_action(@question, @current_user, :delete)
      @question.destroy
      render :json => @question.to_json
    end
  end
  
  def move
    @question = @context.assessment_questions.find(params[:assessment_question_id])
    # Note that a question might be moved to a question bank in another context, so we don't
    # want to scope this lookup to the context. We check permissions on the question bank below.
    @new_bank = AssessmentQuestionBank.find(params[:assessment_question_bank_id])
    if authorized_action(@question, @current_user, :delete) && authorized_action(@new_bank, @current_user, :manage)
      @new_question = @question
      if params[:move] != '1'
        @new_question = @question.clone_for(@new_bank)
      end
      @new_question.context = @new_bank.context
      @new_question.assessment_question_bank = @new_bank
      @new_question.save
      render :json => @new_question.to_json
    end
  end
end
