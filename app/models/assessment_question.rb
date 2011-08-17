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

class AssessmentQuestion < ActiveRecord::Base
  include Workflow
  attr_accessible :name, :question_data, :form_question_data
  has_many :quiz_questions
  has_many :attachments, :as => :context
  belongs_to :context, :polymorphic => true
  belongs_to :assessment_question_bank, :touch => true
  simply_versioned
  adheres_to_policy
  acts_as_list :scope => :assessment_question_bank_id
  before_save :infer_defaults
  after_save :translate_links_if_changed
  validates_length_of :name, :maximum => maximum_string_length, :allow_nil => true
  
  serialize :question_data

  set_policy do
    given{|user, session| cached_context_grants_right?(user, session, :manage_assignments) }
    set { can :read and can :create and can :update and can :delete }
  end
  
  def infer_defaults
    self.question_data ||= {}
    if self.question_data.is_a?(Hash)
      if self.question_data[:question_name].try(:strip).blank?
        self.question_data[:question_name] = "Question"
      end
      self.question_data[:name] = self.question_data[:question_name]
    end
    self.name = self.question_data[:question_name] || self.name
    self.assessment_question_bank ||= AssessmentQuestionBank.unfiled_for_context(self.context)
  end
  
  def translate_links_if_changed
    send_later :translate_links if self.question_data_changed? && !@skip_translate_links
  end
  
  def translate_links(hash=nil, file_substitutions={})
    root = false
    if !hash
      root = true
      hash = self.question_data || {}
    end
    links = Regexp.new("/#{context_type.downcase.pluralize}/#{context_id}/files/(\\d+)/(download|preview)") rescue nil
    hash.each do |key, value|
      if value.is_a?(Hash)
        hash[key] = translate_links(value, file_substitutions)
      elsif value.is_a?(String) && links
        hash[key] = value.gsub(links) do |match|
          if !file_substitutions[$1]
            file = Attachment.find_by_context_type_and_context_id_and_id(context_type, context_id, $1)
            new_file = file.clone_for(self) rescue nil
            new_file.save if new_file
            file_substitutions[$1] = new_file
          end
          if file_substitutions[$1]
            "/assessment_questions/#{self.id}/files/#{file_substitutions[$1].id}/#{file_substitutions[$1].uuid}"
          else
            match
          end
        end
      end
    end
    if root
      @skip_translate_links = true
      self.question_data = hash
      self.save
      @skip_translate_links = false
    end
    hash
  end
  
  def data
    res = self.question_data || {}
    res[:assessment_question_id] = self.id
    res[:question_name] = "Question" if res[:question_name].blank?
    # TODO: there's a potential id conflict here, where if a quiz
    # has some questions manually created and some pulled from a
    # bank, it's possible that a manual question's id could match
    # an assessment_question's id.  This would prevent the user
    # from being able to answer both questions when taking the quiz.
    res[:id] = self.id
    res
  end
  
  workflow do
    state :active
    state :independently_edited
    state :deleted
  end
  
  def form_question_data=(data)
    self.question_data = AssessmentQuestion.parse_question(data, self)
  end
  
  def question_data=(data)
    if data.is_a?(String)
      data = ActiveSupport::JSON.decode(data) rescue nil
    end
    write_attribute(:question_data, data)
  end
  
  def edited_independent_of_quiz_question
    self.workflow_state = 'independently_edited'
  end
  
  def editable_by?(question)
    if self.independently_edited?
      false
    # If the assessment_question was created long before the quiz_question,
    # then the assessment question must have been created on its own, which means
    # it shouldn't be affected by changes to the quiz_question since it wasn't
    # based on the quiz_question to begin with
    elsif !self.new_record? && question.assessment_question_id == self.id && question.created_at && self.created_at < question.created_at + 5.minutes && self.created_at > question.created_at + 30.seconds
      false
    elsif self.assessment_question_bank && self.assessment_question_bank.title != AssessmentQuestionBank::DEFAULT_UNFILED_TITLE
      false
    elsif self.new_record? || (quiz_questions.count <= 1 && question.assessment_question_id == self.id)
      true
    else
      false
    end
  end
  
  def create_quiz_question
    qq = quiz_questions.new
    qq.migration_id = self.migration_id
    qq.write_attribute(:question_data, question_data)
    qq
  end
  
  def self.scrub(text)
    if text && text[-1] == 191 && text[-2] == 187 && text[-3] == 239
      text = text[0..-4]
    end
    text
  end
  
  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    self.save
  end
  
  def self.sanitize(html)
    Sanitize.clean(html || "", Instructure::SanitizeField::SANITIZE)
  end
  
  def self.check_length(html, type, max=16.kilobytes)
    if html && html.length > max
      raise "The text for #{type} is too long, max length is #{max}"
    end
    html
  end
  
  def self.parse_question(qdata, assessment_question=nil)
    question = {}
    qdata = qdata.with_indifferent_access
    previous_data = assessment_question.question_data rescue {}
    question[:points_possible] = (qdata[:points_possible] || previous_data[:points_possible] || 0.0).to_f
    question[:correct_comments] = check_length(qdata[:correct_comments] || previous_data[:correct_comments] || "", 'correct comments', 5.kilobyte)
    question[:incorrect_comments] = check_length(qdata[:incorrect_comments] || previous_data[:incorrect_comments] || "", 'incorrect comments', 5.kilobyte)
    question[:neutral_comments] = check_length(qdata[:neutral_comments], 'neutral comments', 5.kilobyte)
    question[:question_type] = qdata[:question_type] || previous_data[:question_type] || "text_only_question"
    question[:question_name] = qdata[:question_name] || qdata[:name] || previous_data[:question_name] || "Question"
    question[:question_name] = "Question" if question[:question_name].blank?
    question[:question_text] = sanitize(check_length(qdata[:question_text] || previous_data[:question_text] || "Question text", 'question text'))
    min_size = 1.kilobyte
    question[:answers] = []
    reset_local_ids
    qdata[:answers] ||= previous_data[:answers] rescue []
    answers = qdata[:answers].to_a.sort_by{|a| (a[0] || "").gsub(/answer_/, "").to_i || ""}
    if question[:question_type] == "multiple_choice_question"
      found_correct = false
      answers.each do |key, answer|
        found_correct = true if answer[:answer_weight].to_i == 100
        a = {:text => check_length(answer[:answer_text], 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => answer[:answer_weight].to_f, :id => unique_local_id(answer[:id].to_i)}
        question[:answers] << a
      end
      question[:answers][0][:weight] = 100 unless found_correct
    elsif question[:question_type] == "true_false_question"
      correct_answer = true
      true_comments = ""
      true_id = nil
      false_comments = ""
      false_id = nil
      answers.each do |key, answer|
        if key != answers[0][0]
          false_comments = check_length(answer[:answer_comments], 'answer comments', min_size)
          false_id = unique_local_id(answer[:id].to_i)
        else
          true_comments = check_length(answer[:answer_comments], 'answer comments', min_size)
          true_id = unique_local_id(answer[:id].to_i)
        end
        if key != answers[0][0] && answer[:answer_weight].to_i == 100
          correct_answer = false
        end
      end
      t = {:text => "True", :comments => true_comments, :weight => (correct_answer ? 100 : 0), :id => true_id}
      f = {:text => "False", :comments => false_comments, :weight => (!correct_answer ? 100 : 0), :id => false_id}
      question[:answers] << t
      question[:answers] << f
    elsif question[:question_type] == "short_answer_question"
      answers.each do |key, answer|
        a = {:text => check_length(scrub(answer[:answer_text]), 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => 100, :id => unique_local_id(answer[:id].to_i)}
        question[:answers] << a
      end
    elsif question[:question_type] == "essay_question"
      question[:comments] = check_length((qdata[:answers][0][:answer_comments] rescue ""), 'essay comments', 5.kilobyte)
    elsif question[:question_type] == "matching_question"
      answers.each do |key, answer|
        a = {:text => check_length(answer[:answer_match_left], 'answer match', min_size), :left => check_length(answer[:answer_match_left], 'answer match', min_size), :right => check_length(answer[:answer_match_right], 'answer match', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size)}
        a[:match_id] = unique_local_id(answer[:match_id].to_i)
        a[:id] = unique_local_id(answer[:id].to_i)
        question[:answers] << a
        question[:matches] ||= []
        question[:matches] << {:match_id => a[:match_id], :text => check_length(answer[:answer_match_right], 'answer match', min_size) }
      end
      (qdata[:matching_answer_incorrect_matches] || "").split("\n").each do |other|
        m = {:text => check_length(other[0..255], 'distractor', min_size) }
        m[:match_id] = previous_data[:answers].detect{|a| a[:text] == m[:text] }[:id] rescue nil
        m[:match_id] = unique_local_id(m[:match_id])
        question[:matches] << m
      end
    elsif question[:question_type] == "missing_word_question"
      found_correct = false
      answers.each do |key, answer|
        found_correct = true if answer[:answer_weight].to_i == 100
        a = {:text => check_length(answer[:answer_text], 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => answer[:answer_weight].to_f, :id => unique_local_id(answer[:id].to_i)}
        question[:answers] << a
      end
      question[:answers][0][:weight] = 100 unless found_correct
      question[:text_after_answers] = sanitize(check_length(qdata[:text_after_answers] || previous_data[:text_after_answers] || "", 'text after answers', 16.kilobytes))
    elsif question[:question_type] == "multiple_dropdowns_question"
      variables = {}
      answers.each_with_index do |arr, idx| 
        key, answer = arr
        answers[idx][1][:blank_id] = check_length(answers[idx][1][:blank_id], 'blank id', min_size)
      end
      answers.each do |key, answer| 
        variables[answer[:blank_id]] ||= false
        variables[answer[:blank_id]] = true if answer[:answer_weight].to_i == 100
        a = {:text => check_length(answer[:answer_text], 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => answer[:answer_weight].to_f, :blank_id => answer[:blank_id], :id => unique_local_id(answer[:id].to_i)}
        question[:answers] << a
      end
      variables.each do |variable, found_correct|
        if !found_correct
          question[:answers].each_with_index do |answer, idx|
            if answer[:blank_id] == variable && !found_correct
              question[:answers][idx][:weight] = 100
              found_correct = true
            end
          end
        end
      end
    elsif question[:question_type] == "fill_in_multiple_blanks_question"
      answers.each do |key, answer|
        a = {:text => check_length(scrub(answer[:answer_text]), 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => answer[:answer_weight].to_f, :blank_id => check_length(answer[:blank_id], 'blank id', min_size), :id => unique_local_id(answer[:id].to_i)}
        question[:answers] << a
      end
    elsif question[:question_type] == "numerical_question"
      answers.each do |key, answer|
        a = {:text => check_length(answer[:answer_text], 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => 100, :id => unique_local_id(answer[:id].to_i)}
        a[:numerical_answer_type] = answer[:numerical_answer_type]
        if answer[:numerical_answer_type] == "exact_answer"
          a[:exact] = answer[:answer_exact].to_f
          a[:margin] = answer[:answer_error_margin].to_f
        else
          a[:numerical_answer_type] = "range_answer"
          a[:start] = answer[:answer_range_start].to_f
          a[:end] = answer[:answer_range_end].to_f
        end
        question[:answers] << a
      end
    elsif question[:question_type] == "calculated_question"
      question[:formulas] = []
      qdata[:formulas].sort_by(&:first).each do |key, formula|
        question[:formulas] << {
          :formula => check_length(formula[0..1024], 'formula', min_size)
        }
      end
      question[:variables] = []
      qdata[:variables].sort_by{|k, v| k[9..-1].to_i}.each do |key, variable|
        question[:variables] << {
          :name => check_length(variable[:name][0..1024], 'variable', min_size),
          :min => variable[:min].to_f,
          :max => variable[:max].to_f,
          :scale => variable[:scale].to_i
        }
      end
      question[:answer_tolerance] = qdata[:answer_tolerance].to_f
      question[:formula_decimal_places] = qdata[:formula_decimal_places].to_i
      answers.each do |key, answer|
        obj = {:weight => 100, :variables => []}
        obj[:answer] = answer[:answer_text].to_f
        answer[:variables].sort_by{|k, v| k[9..-1].to_i}.each do |key2, variable|
          obj[:variables] << {
            :name => check_length(variable[:name], 'variable', min_size),
            :value => variable[:value].to_f
          }
        end
        question[:answers] << obj
      end
    elsif question[:question_type] == "multiple_answers_question"
      found_correct = false
      answers.each do |key, answer|
        found_correct = true if answer[:answer_weight].to_i == 100
        a = {:text => check_length(answer[:answer_text], 'answer text', min_size), :comments => check_length(answer[:answer_comments], 'answer comments', min_size), :weight => answer[:answer_weight].to_f, :id => unique_local_id(answer[:id].to_i)}
        question[:answers] << a
      end
      question[:answers][0][:weight] = 100 unless found_correct
    elsif question[:question_type] == "text_only_question"
      question[:points_possible] = 0
    else
    end
    question[:answers].each_index do |idx|
      question[:answers][idx][:id] ||= unique_local_id
    end
    question[:assessment_question_id] = assessment_question.id rescue nil
    return question
  end
  
  def self.update_question(assessment_question, qdata)
    question = parse_question(qdata, assessment_question)
    assessment_question.question_data = question
    assessment_question.name = question[:question_name]
    assessment_question.save
    question[:assessment_question_id] = assessment_question.id
    question
  end
  
  def self.variable_id(variable)
    Digest::MD5.hexdigest(["dropdown", variable, "instructure-key"].join(","))
  end
  
  def self.unique_local_id(suggested_id=nil)
    @@ids ||= {}
    if suggested_id && suggested_id > 0 && !@@ids[suggested_id]
      @@ids[suggested_id] = true
      return suggested_id
    end
    id = rand(10000)
    while @@ids[id]
      id = rand(10000)
    end
    @@ids[id] = true
    id
  end
  
  def self.reset_local_ids
    @@ids = {}
  end
  
  def clone_for(question_bank, dup=nil, options={})
    dup ||= AssessmentQuestion.new
    self.attributes.delete_if{|k,v| [:id, :question_data].include?(k.to_sym) }.each do |key, val|
      dup.send("#{key}=", val)
    end
    dup.context = question_bank.context
    dup.assessment_question_bank_id = question_bank
    dup.write_attribute(:question_data, self.question_data)
    dup
  end

  def self.process_migration(data, migration)
    question_data = {}
    questions = data['assessment_questions'] ? data['assessment_questions']['assessment_questions'] : []
    questions ||= []
    to_import = migration.to_import 'quizzes'
    total = questions.length

    # If a question doesn't have a specified question bank
    # we want to put it in a bank named after the assessment it's in
    bank_map = {}
    assessments = data['assessments'] ? data['assessments']['assessments'] : []
    assessments.each do |assmnt|
      next unless assmnt['questions']
      assmnt['questions'].each do |q|
        if q["question_type"] == "question_reference"
          bank_map[q['migration_id']] = assmnt['title'] if q['migration_id']
        elsif q["question_type"] == "question_group"
          q['questions'].each do |ref|
            bank_map[ref['migration_id']] = assmnt['title'] if ref['migration_id']
          end
        end
      end
    end

    if migration.to_import('assessment_questions') != false || (to_import && !to_import.empty?)
      if check = questions.first
        # we don't re-migrate questions
        if AssessmentQuestion.find_all_by_context_id_and_migration_id(migration.context.id, check['migration_id']).count > 0
          return question_data
        end
      end
      logger.debug "adding #{total} assessment questions"

      banks = {}
      questions.each do |question|
        question[:question_bank_name] = nil if question[:question_bank_name] == ''
        question[:question_bank_name] ||= bank_map[question[:migration_id]]
        question[:question_bank_name] ||= migration.question_bank_name
        question[:question_bank_name] ||= AssessmentQuestionBank::DEFAULT_IMPORTED_TITLE
        hash_id = "#{question[:question_bank_id]}_#{question[:question_bank_name]}"
        if !banks[hash_id]
            unless bank = AssessmentQuestionBank.find_by_context_type_and_context_id_and_title_and_migration_id(migration.context.class.to_s, migration.context.id, question[:question_bank_name], question[:question_bank_id])
              bank = migration.context.assessment_question_banks.new
              bank.title = question[:question_bank_name]
              bank.migration_id = question[:question_bank_id]
              bank.save!
            end
            banks[hash_id] = bank
        end

        question = AssessmentQuestion.import_from_migration(question, migration.context, banks[hash_id])
        question_data[question['migration_id']] = question
      end
    end

    question_data
  end

  def self.import_from_migration(hash, context, bank=nil, options={})
    hash = hash.with_indifferent_access
    if !bank
      hash[:question_bank_name] = nil if hash[:question_bank_name] == ''
      hash[:question_bank_name] ||= AssessmentQuestionBank::DEFAULT_IMPORTED_TITLE
      unless bank = AssessmentQuestionBank.find_by_context_type_and_context_id_and_title_and_migration_id(context.class.to_s, context.id, hash[:question_bank_name], hash[:question_bank_id])
        bank ||= context.assessment_question_banks.new
        bank.title = hash[:question_bank_name]
        bank.migration_id = hash[:question_bank_id]
        bank.save!
      end
    end
    hash[:question_text] = ImportedHtmlConverter.convert(hash[:question_text], context) if hash[:question_text]
    question_data = ActiveRecord::Base.connection.quote hash.to_yaml
    question_name = ActiveRecord::Base.connection.quote hash[:question_name]
    query = "INSERT INTO assessment_questions (name, question_data, context_id, context_type, workflow_state, created_at, updated_at, assessment_question_bank_id, migration_id)"
    query += " VALUES (#{question_name},#{question_data},#{context.id},'#{context.class}','active', '#{Time.now.to_s(:db)}', '#{Time.now.to_s(:db)}', #{bank.id}, '#{hash[:migration_id]}')"
    id = ActiveRecord::Base.connection.insert(query)
    hash['assessment_question_id'] = id
    hash
  end
  
  named_scope :active, lambda {
    {:conditions => ['assessment_questions.workflow_state != ?', 'deleted'] }
  }
end
