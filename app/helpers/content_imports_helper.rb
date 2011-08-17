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

module ContentImportsHelper
  def question_banks_select_list
    question_banks = @context.assessment_question_banks.active.scoped(:select=>'title', :order=>'title').map(&:title)
    question_banks.delete AssessmentQuestionBank::DEFAULT_IMPORTED_TITLE
    question_banks.insert 0, AssessmentQuestionBank::DEFAULT_IMPORTED_TITLE
    question_banks
  end

  def qti_enabled?
    if plugin = Canvas::Plugin.find(:qti_exporter)
      return plugin.settings[:enabled].to_s == 'true'
    end
    false
  end

  def exports_enabled?
    Canvas::Plugin.all_for_tag(:export_system).length > 0
  end

  def qti_or_content_link
    if params[:return_to]
      clean_return_to(params[:return_to])
    elsif qti_enabled?
      context_url(@context, :context_import_quizzes_url)
    else
      context_url(@context, :context_url)
    end
  end
end
