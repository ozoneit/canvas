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

module QuizzesHelper
  def answer_type(question)
    return OpenObject.new unless question
    @answer_types_lookup ||= {
      "multiple_choice_question" => OpenObject.new({
        :question_type => "multiple_choice_question",
        :entry_type => "radio",
        :display_answers => "multiple",
        :answer_type => "select_answer"
      }),
      "true_false_question" => OpenObject.new({
        :question_type => "true_false_question",
        :entry_type => "radio",
        :display_answers => "multiple",
        :answer_type => "select_answer"
      }),
      "short_answer_question" => OpenObject.new({
        :question_type => "short_answer_question",
        :entry_type => "text_box",
        :display_answers => "single",
        :answer_type => "select_answer"
      }),
      "essay_question" => OpenObject.new({
        :question_type => "essay_question",
        :entry_type => "textarea",
        :display_answers => "single",
        :answer_type => "text_answer"
      }),
      "matching_question" => OpenObject.new({
        :question_type => "matching_question",
        :entry_type => "matching",
        :display_answers => "multiple",
        :answer_type => "matching_answer"
      }),
      "missing_word_question" => OpenObject.new({
        :question_type => "missing_word_question",
        :entry_type => "select",
        :display_answers => "multiple",
        :answer_type => "select_answer"
      }),
      "numerical_question" => OpenObject.new({
        :question_type => "numerical_question",
        :entry_type => "numerical_text_box",
        :display_answers => "single",
        :answer_type => "numerical_answer"
      }),
      "calculated_question" => OpenObject.new({
        :question_type => "calculated_question",
        :entry_type => "numerical_text_box",
        :display_answers => "single",
        :answer_type => "numerical_answer"
      }),
      "multiple_answers_question" => OpenObject.new({
        :question_type => "multiple_answers_question",
        :entry_type => "checkbox",
        :display_answers => "multiple",
        :answer_type => "select_answer"
      }),
      "fill_in_multiple_blanks_question" => OpenObject.new({
        :question_type => "fill_in_multiple_blanks_question",
        :entry_type => "text_box",
        :display_answers => "multiple",
        :answer_type => "select_answer",
        :multiple_sets => true
      }),
      "multiple_dropdowns_question" => OpenObject.new({
        :question_type => "multiple_dropdowns_question",
        :entry_type => "select",
        :display_answers => "none",
        :answer_type => "select_answer",
        :multiple_sets => true
      }),
      "other" =>  OpenObject.new({
        :question_type => "text_only_question",
        :entry_type => "none",
        :display_answers => "none",
        :answer_type => "none"
      })
    }
    res = @answer_types_lookup[question[:question_type]] || @answer_types_lookup["other"]
    if res.question_type == "text_only_question"
      res.unsupported = question[:question_type] != "text_only_question"
    end
    res
  end
end
