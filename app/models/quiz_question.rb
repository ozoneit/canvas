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

class QuizQuestion < ActiveRecord::Base
  attr_accessible :quiz, :quiz_group, :assessment_question, :question_data, :assessment_question_version, :quiz_group, :quiz
  attr_readonly :quiz_id
  belongs_to :quiz
  belongs_to :assessment_question
  belongs_to :quiz_group
  before_save :infer_defaults
  before_save :create_assessment_question
  before_destroy :delete_assessment_question
  validates_presence_of :quiz_id
  serialize :question_data
  after_save :update_quiz
  
  def infer_defaults
    if !self.position && self.quiz
      if self.quiz_group
        self.position = (self.quiz_group.quiz_questions.map(&:position).compact.max || 0) + 1
      else
        self.position = self.quiz.root_entries_max_position + 1
      end
    end
    if self.question_data.is_a?(Hash) 
      if self.question_data[:question_name].try(:strip).blank?
        self.question_data[:question_name] = "Question"
      end
      self.question_data[:name] = self.question_data[:question_name]
    end
    if self.question_data && self.question_data[:question_text]
      config = Instructure::SanitizeField::SANITIZE
      self.question_data[:question_text] = Sanitize.clean(self.question_data[:question_text], config)
    end
  end
  protected :infer_defaults
  
  def update_quiz
    Quiz.update_all({:last_edited_at => Time.now}, {:id => self.quiz_id})
  end
  
  def question_data=(data)
    if data.is_a?(String)
      data = ActiveSupport::JSON.decode(data) rescue nil
    end
    return if data == self.question_data
    data = AssessmentQuestion.parse_question(data, self.assessment_question)
    data[:name] = data[:question_name]
    write_attribute(:question_data, data)
  end
  
  def delete_assessment_question
    if self.assessment_question && self.assessment_question.editable_by?(self)
      self.assessment_question.destroy
    end
  end
  
  def create_assessment_question
    return if self.question_data && self.question_data[:question_type] == 'text_only_question'
    self.assessment_question ||= AssessmentQuestion.new
    if self.assessment_question.editable_by?(self)
      self.assessment_question.question_data = self.question_data
      self.assessment_question.context = self.quiz.context if self.quiz && self.quiz.context
      self.assessment_question.save if self.assessment_question.new_record?
      self.assessment_question_id = self.assessment_question.id
      self.assessment_question_version = self.assessment_question.version_number rescue nil
    end
    true
  end
  
  def self.migrate_question_hash(hash, params)
    if params[:old_context] && params[:new_context]
      [:question_text, :text_after_answers].each do |key|
        hash[key] = Course.migrate_content_links(hash[key], params[:old_context], params[:new_context]) if hash[key]
      end
    elsif params[:context] && params[:user]
      [:question_text, :text_after_answers].each do |key|
        hash[key] = Course.copy_authorized_content(hash[key], params[:context], params[:user]) if hash[key]
      end
    end
    
    hash
  end
  
  def clone_for(quiz, dup=nil, options={})
    dup ||= QuizQuestion.new
    self.attributes.delete_if{|k,v| [:id, :quiz_id, :quiz_group_id, :question_data].include?(k.to_sym) }.each do |key, val|
      dup.send("#{key}=", val)
    end
    data = self.question_data || {}
    if options[:old_context] && options[:new_context]
      data = QuizQuestion.migrate_question_hash(data, options)
    end
    dup.write_attribute(:question_data, data)
    dup.quiz_id = quiz.id
    dup
  end

  # QuizQuestion.data is used when creating and editing a quiz, but 
  # once the quiz is "saved" then the "rendered" version of the
  # quiz is stored in Quiz.quiz_data.  Hence, the teacher can
  # be futzing with questions and groups and not affect
  # the quiz, as students see it.
  def data
    res = (self.question_data || self.assessment_question.question_data) rescue {}
    res[:assessment_question_id] = self.assessment_question_id
    res[:question_name] = "Question" if res[:question_name].blank?
    res[:id] = self.id
    res.with_indifferent_access
  end

  def self.import_from_migration(hash, context, quiz=nil, quiz_group=nil)
    question_data = ActiveRecord::Base.connection.quote hash.to_yaml
    query = "INSERT INTO quiz_questions (quiz_id, quiz_group_id, assessment_question_id, question_data, created_at, updated_at, migration_id)"
    query += " VALUES (#{quiz ? quiz.id : 'NULL'}, #{quiz_group ? quiz_group.id : 'NULL'}, #{hash['assessment_question_id']},#{question_data},'#{Time.now.to_s(:db)}', '#{Time.now.to_s(:db)}', '#{hash[:migration_id]}')"
    id = ActiveRecord::Base.connection.insert(query)
    hash[:quiz_question_id] = id
    hash
  end
end
