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

class Quiz < ActiveRecord::Base
  include Workflow
  include HasContentTags
  include CopyAuthorizedLinks
  include ActionView::Helpers::SanitizeHelper
  extend ActionView::Helpers::SanitizeHelper::ClassMethods
  attr_accessible :title, :description, :points_possible, :assignment_id, :shuffle_answers,
    :show_correct_answers, :time_limit, :allowed_attempts, :scoring_policy, :quiz_type,
    :lock_at, :unlock_at, :due_at, :access_code, :anonymous_submissions, :assignment_group_id,
    :hide_results, :locked, :ip_filter, :require_lockdown_browser, :context

  attr_readonly :context_id, :context_type
  
  has_many :quiz_questions, :dependent => :destroy, :order => 'position'
  has_many :quiz_submissions, :dependent => :destroy
  has_many :quiz_groups, :dependent => :destroy, :order => 'position'
  has_one :context_module_tag, :as => :content, :class_name => 'ContentTag', :conditions => ['content_tags.tag_type = ? AND workflow_state != ?', 'context_module', 'deleted'], :include => {:context_module => [:context_module_progressions, :content_tags]}
  belongs_to :context, :polymorphic => true
  belongs_to :assignment
  belongs_to :cloned_item
  adheres_to_policy
  validates_length_of :description, :maximum => maximum_long_text_length, :allow_nil => true, :allow_blank => true
  validates_length_of :title, :maximum => maximum_string_length, :allow_nil => true
  validates_presence_of :context_id
  validates_presence_of :context_type
  
  sanitize_field :description, Instructure::SanitizeField::SANITIZE
  copy_authorized_links(:description) { [self.context, nil] }
  before_save :set_defaults
  before_save :build_assignment
  after_save :update_assignment
  after_save :touch_context
  
  serialize :quiz_data
  
  simply_versioned

  def infer_times
    # set the time to 11:59 pm in the creator's time zone, if none given
    self.due_at += ((60 * 60 * 24) - 60) if self.due_at && self.due_at.hour == 0 && self.due_at.min == 0
    self.lock_at += ((60 * 60 * 24) - 60) if self.lock_at && self.lock_at.hour == 0 && self.lock_at.min == 0
  end

  def set_defaults
    self.shuffle_answers = false if self.shuffle_answers == nil
    self.show_correct_answers = true if self.show_correct_answers == nil
    self.allowed_attempts = 1 if self.allowed_attempts == nil
    self.scoring_policy = "keep_highest" if self.scoring_policy == nil
    self.due_at ||= [[self.lock_at, self.due_at].compact.min, self.unlock_at].compact.max
    self.ip_filter = nil if self.ip_filter && self.ip_filter.strip.empty?
    if !self.available? && self.quiz_type != 'survey' && self.quiz_type != 'graded_survey'
      self.points_possible = self.current_points_possible
    end
    self.title = "Unnamed Quiz" if self.title.blank?
    self.quiz_type ||= "assignment"
    self.last_assignment_id = self.assignment_id_was if self.assignment_id_was
    if (!graded? && self.assignment_id) || (self.assignment_id_was && self.assignment_id != self.assignment_id_was)
      @old_assignment_id = self.assignment_id_was
      self.assignment_id = nil
    end
    self.assignment_group_id ||= self.assignment.assignment_group_id if self.assignment
    self.question_count = self.question_count(true)
    @update_existing_submissions = true if self.for_assignment? && self.quiz_type_changed?
    @stored_questions = nil
  end
  protected :set_defaults
  
  def build_assignment
    if self.available? && !self.assignment_id && self.graded? && @saved_by != :assignment
      assignment = self.assignment
      assignment ||= self.context.assignments.build(:title => self.title, :due_at => self.due_at, :submission_types => 'online_quiz')
      assignment.assignment_group_id = self.assignment_group_id
      assignment.saved_by = :quiz
      assignment.save
      self.assignment_id = assignment.id
    end
  end
  
  def readable_type
    (self.quiz_type || "").match(/survey/) ? "Survey" : "Quiz"
  end
  
  def valid_ip?(ip)
    require 'ipaddr'
    ip_filter.split(/,/).any? do |filter|
      addr_range = IPAddr.new(filter) rescue nil
      addr = IPAddr.new(ip) rescue nil
      addr && addr_range && addr_range.include?(addr)
    end
  end
  
  def survey?
    self.quiz_type && self.quiz_type.match(/survey/)
  end
  
  def current_points_possible
    entries = self.root_entries
    possible = 0
    entries.each do |e|
      if e[:question_points]
        possible += (e[:question_points].to_f * e[:actual_pick_count])
      else
        possible += e[:points_possible].to_f unless e[:unsupported]
      end
    end
    possible = self.assignment.points_possible if entries.empty? && self.assignment
    possible
  end
  
  def set_unpublished_question_count
    entries = self.root_entries
    cnt = 0
    entries.each do |e|
      if e[:question_points]
        cnt += e[:actual_pick_count]
      else
        cnt += 1 unless e[:unsupported]
      end
    end

    # TODO: this is hacky, but we don't want callbacks to run because we're in an after_save. Refactor.
    Quiz.update_all({ :unpublished_question_count => cnt }, { :id => self.id })
    self.unpublished_question_count = cnt
  rescue => e
  end
  
  def for_assignment?
    self.assignment_id && self.assignment && self.assignment.submission_types == 'online_quiz'
  end

  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    # self.deleted_at = Time.now
    res = self.save
    if self.for_assignment?
      self.assignment.destroy unless self.assignment.deleted?
    end
    res
  end
  
  def restore
    self.workflow_state = 'edited'
    self.save
    self.assignment.restore(:quiz)
  end
  
  def unlink_from(type)
    @saved_by = type
    if self.root_entries.empty? && !self.available?
      self.assignment_id = nil
      self.destroy 
    else
      self.assignment_id = nil
      self.save
    end
  end
  
  def assignment_id=(val)
    @assignment_id_set = true
    write_attribute(:assignment_id, val)
  end
  
  def graded?
    self.quiz_type == 'assignment' || self.quiz_type == 'graded_survey'
  end
  
  def update_existing_submissions
    # If the quiz suddenly changes from non-graded to graded,
    # then this will update the existing submissions to reflect quiz
    # scores in the gradebook.
    self.quiz_submissions.each{|s| s.touch }
  end
  
  attr_accessor :saved_by
  def update_assignment
    send_later_if_production(:set_unpublished_question_count) if self.id
    if !self.assignment_id && @old_assignment_id && self.context_module_tag
      self.context_module_tag.confirm_valid_module_requirements
    end
    if !self.graded? && (@old_assignment_id || self.last_assignment_id)
      Assignment.update_all({:workflow_state => 'deleted', :updated_at => Time.now}, {:id => [@old_assignment_id, self.last_assignment_id].compact})
      ContentTag.delete_for(Assignment.find(@old_assignment_id)) if @old_assignment_id
      ContentTag.delete_for(Assignment.find(self.last_assignment_id)) if self.last_assignment_id
    end
    if @update_existing_submissions
      send_later(:update_existing_submissions)
    end
    if self.assignment && (@assignment_id_set || self.for_assignment?) && @saved_by != :assignment
      if !self.graded? && @old_assignment_id
      else
        conn = ActiveRecord::Base.connection
        Quiz.update_all({:workflow_state => 'deleted', :assignment_id => nil, :updated_at => Time.now.utc}, ["assignment_id = ? AND id != ?", self.assignment_id, self.id]) if self.assignment_id
        a = self.assignment
        a.points_possible = self.points_possible
        a.description = self.description
        a.title = self.title
        a.due_at = self.due_at
        a.lock_at = self.lock_at
        a.unlock_at = self.unlock_at
        a.submission_types = "online_quiz"
        a.assignment_group_id = self.assignment_group_id
        a.saved_by = :quiz
        a.workflow_state = 'available' if a.deleted?
        a.with_versioning(false) do
          a.save
        end
        self.assignment_id = a.id
        Quiz.update_all({:assignment_id => a.id}, {:id => self.id})
      end
    end
  end
  protected :update_assignment
  
  workflow do
    state :created do
      event :did_edit, :transitions_to => :edited
    end
    
    state :edited do
      event :offer, :transitions_to => :available
    end
    
    state :available
    state :deleted
  end
  
  def root_entries_max_position
    question_max = self.quiz_questions.maximum(:position, :conditions => 'quiz_group_id is null')
    group_max = self.quiz_groups.maximum(:position)
    [question_max, group_max, 0].compact.max
  end
  
  # Returns the list of all "root" entries, either questions or question
  # groups for this quiz.  This is PRE-SAVED data.  Once the quiz has 
  # been saved, all the data can be found in Quiz.quiz_data
  def root_entries(force_check=false)
    return @root_entries if @root_entries && !force_check
    result = []
    all_questions = self.quiz_questions
    result.concat all_questions.select{|q| !q.quiz_group_id }
    result.concat self.quiz_groups
    result = result.sort_by{|e| e.position || 99999}.map do |e|
      res = nil
      if e.is_a? QuizQuestion
        res = e.data
      else #it's a QuizGroup
        data = e.attributes.with_indifferent_access
        data[:entry_type] = "quiz_group"
        if e.assessment_question_bank_id
          data[:assessment_question_bank_id] = e.assessment_question_bank_id
          data[:questions] = []
        else
          data[:questions] = e.quiz_questions.map{|q| q.data}
        end
        data[:actual_pick_count] = e.actual_pick_count
        res = data
      end
      res[:position] = e.position.to_i
      res
    end
    @root_entries = result
  end
  
  # Returns the number of questions a student will see on the
  # SAVED version of the quiz
  def question_count(force_check=false)
    return read_attribute(:question_count) if !force_check && read_attribute(:question_count)
    question_count = 0
    self.stored_questions.each do |q|
      if q[:pick_count]
        question_count += q[:actual_pick_count] || q[:pick_count]
      else
        question_count += 1 unless q[:question_type] == "text_only_question"
      end
    end
    question_count || 0
  end
  
  # Returns data for the SAVED version of the quiz.  That is, not
  # the version found by gathering relationships on the Quiz data models,
  # but the version being held in Quiz.quiz_data.  Caches the result
  # in @stored_questions.
  def stored_questions(hashes=nil)
    non_shuffled_questions = ["true_false_question", "matching_question"]
    res = []
    return @stored_questions if @stored_questions && !hashes
    questions = hashes || self.quiz_data || []
    questions.each do |val|
      
      if val[:answers]
        val[:answers] = val[:answers].sort_by{|a| rand} if self.shuffle_answers && !non_shuffled_questions.include?(val[:question_type])
        val[:matches] = val[:matches].sort_by{|m| m[:text] || "" } if val[:matches]
      elsif val[:questions] # It's a QuizGroup
        if val[:assessment_question_bank_id]
          # It points to a question bank
          # question/answer/match shuffling happens when a submission is generated
        else #normal QuizGroup
          questions = []
          val[:questions].each do |question|
            if question[:answers]
              question[:answers] = question[:answers].sort_by{|a| rand} if self.shuffle_answers && !non_shuffled_questions.include?(question[:question_type])
              question[:matches] = question[:matches].sort_by{|m| m[:text] || ""} if question[:matches]
            end
            questions << question
          end
          questions = questions.sort_by{|q| rand}
          val[:questions] = questions
        end
      end
      res << val
    end
    @stored_questions = res
    res
  end
  
  def single_attempt?
    self.allowed_attempts == 1
  end
  
  def unlimited_attempts?
    self.allowed_attempts == -1
  end
  
  def generate_submission_question(q)
    @idx ||= 1
    q[:name] = "Question #{@idx}"
    if q[:question_type] == 'text_only_question'
      q[:name] = "Spacer"
      @idx -= 1
    elsif q[:question_type] == 'fill_in_multiple_blanks_question'
      text = q[:question_text]
      variables = q[:answers].map{|a| a[:blank_id] }.uniq
      variables.each do |variable|
        variable_id = AssessmentQuestion.variable_id(variable)
        re = Regexp.new("\\[#{variable}\\]")
        text = text.sub(re, "<input class='question_input' type='text' style='width: 120px;' name='question_#{q[:id]}_#{variable_id}'/>")
      end
      q[:original_question_text] = q[:question_text]
      q[:question_text] = text
    elsif q[:question_type] == 'multiple_dropdowns_question'
      text = q[:question_text]
      variables = q[:answers].map{|a| a[:blank_id] }.uniq
      variables.each do |variable|
        variable_id = AssessmentQuestion.variable_id(variable)
        variable_answers = q[:answers].select{|a| a[:blank_id] == variable }
        options = variable_answers.map{|a| "<option value='#{a[:id]}'>#{CGI::escapeHTML(a[:text])}</option>" }
        select = "<select class='question_input' name='question_#{q[:id]}_#{variable_id}'><option value=''>[ Select ]</option>#{options}</select>"
        re = Regexp.new("\\[#{variable}\\]")
        text = text.sub(re, select)
      end
      q[:original_question_text] = q[:question_text]
      q[:question_text] = text
    # on equation questions, pick one of the formulas, plug it in
    # and you should be able to treat it like a numerical_answer
    # question for all intents and purposes
    elsif q[:question_type] == 'calculated_question'
      text = q[:question_text]
      q[:answers] = [q[:answers].sort_by{|a| rand }.first].compact
      if q[:answers].first
        q[:answers].first[:variables].each do |variable|
          re = Regexp.new("\\[#{variable[:name]}\\]")
          text = text.gsub(re, variable[:value].to_s)
        end
      end
      q[:question_text] = text
    end
    q[:question_name] = q[:name]
    @idx += 1
    q
  end
  
  def find_or_create_submission(user, temporary=false, state=nil)
    s = nil
    state ||= 'untaken'
    attempts = 0
    user_id = user.is_a?(User) ? user.id : user
    begin
      if temporary || !user.is_a?(User)
        user_code = "#{user.to_s}"
        user_code = "user_#{user.id}" if user.is_a?(User)
        s = QuizSubmission.find_or_initialize_by_quiz_id_and_temporary_user_code(self.id, user_code)
        s.workflow_state ||= state
        s.save
      else
        s = QuizSubmission.find_or_initialize_by_quiz_id_and_user_id(self.id, user_id)
        s.workflow_state ||= state
        s.save
      end
    rescue => e
      attempts += 1
      retry if attempts < 3
    end
    s
  end
  
  # Generates a submission for the specified user on this quiz, based
  # on the SAVED version of the quiz.  Does not consider permissions.
  def generate_submission(user, preview=false)
    submission = nil
    submission = self.find_or_create_submission(user, preview)
    submission.retake
    submission.attempt = (submission.attempt + 1) rescue 1
    user_questions = []
    @idx = 1
    @stored_questions = nil
    @submission_questions = self.stored_questions
    if preview
      @submission_questions = self.stored_questions(generate_quiz_data(:persist => false))
    end
    
    @submission_questions.each do |q|
      if q[:pick_count] #QuizGroup
        if q[:assessment_question_bank_id]
          bank = AssessmentQuestionBank.find_by_id(q[:assessment_question_bank_id])
          if bank
            questions = bank.select_for_submission(q[:pick_count])
            questions = questions.map{|aq| aq.data}
            questions.each do |question|
              if question[:answers]
                question[:answers] = question[:answers].sort_by{|a| rand} if self.shuffle_answers && !non_shuffled_questions.include?(question[:question_type])
                question[:matches] = question[:matches].sort_by{|m| m[:text] || ""} if question[:matches]
              end
              question[:points_possible] = q[:question_points]
              question[:published_at] = q[:published_at]
              user_questions << generate_submission_question(question)
            end
          end
        else
          q[:pick_count].times do |i|
            if q[:questions][i]
              question = q[:questions][i]
              question[:points_possible] = q[:question_points]
              user_questions << generate_submission_question(question)
            end
          end
        end
      else #just a question
        user_questions << generate_submission_question(q)
      end
    end
    submission.score = nil
    submission.fudge_points = nil
    submission.quiz_data = user_questions
    submission.quiz_version = self.version_number
    submission.started_at = Time.now
    submission.end_at = nil
    submission.end_at = submission.started_at + (self.time_limit.to_f * 60.0) if self.time_limit
    # Admins can take the full quiz whenever they want
    unless user.is_a?(User) && self.grants_right?(user, nil, :grade)
      submission.end_at = self.due_at if self.due_at && Time.now < self.due_at && (!submission.end_at || self.due_at < submission.end_at)
    end
    submission.end_at += (submission.extra_time * 60.0) if submission.end_at && submission.extra_time
    submission.finished_at = nil
    submission.submission_data = {}
    submission.workflow_state = 'preview' if preview
    submission.save
    submission
  end
  
  # Takes the PRE-SAVED version of the quiz and uses it to generate a 
  # SAVED version.  That is, gathers the relationship entities from
  # the database and uses them to populate a static version that will
  # be held in Quiz.quiz_data
  def generate_quiz_data(opts={})
    entries = self.root_entries(true)
    possible = 0
    t = Time.now
    entries.each do |e|
      if e[:question_points] #QuizGroup
        possible += (e[:question_points].to_f * e[:actual_pick_count])
      else
        possible += e[:points_possible].to_f
      end
      e[:published_at] = t
    end
    data = entries
    if opts[:persist] != false
      self.quiz_data = data
      if self.quiz_type != 'survey' && self.quiz_type != 'graded_survey'
        self.points_possible = possible
      end
      self.allowed_attempts ||= 1
      check_if_submissions_need_review
    end
    data
  end
  
  def add_assessment_questions(assessment_questions, group=nil)
    questions = assessment_questions.map do |assessment_question|
      question = self.quiz_questions.build
      question.quiz_group_id = group.id if group && group.quiz_id == self.id
      question.write_attribute(:question_data, assessment_question.question_data)
      question.assessment_question = assessment_question
      question.assessment_question_version = assessment_question.version_number
      question.save
      question
    end
    questions.compact.uniq
  end
  
  def quiz_title
    result = self.title
    result = "Unnamed Quiz" if result == "undefined" || !result
    result = self.assignment.title if self.assignment
    result
  end
  alias_method :to_s, :quiz_title
  
  def locked_for?(user=nil, opts={})
    @locks ||= {}
    return false if opts[:check_policies] && self.grants_right?(user, nil, :update)
    @locks[user ? user.id : 0] ||= Rails.cache.fetch(['_locked_for', self, user].cache_key, :expires_in => 1.minute) do
      locked = false
      if (self.unlock_at && self.unlock_at > Time.now)
        sub = user && quiz_submissions.find_by_user_id(user.id)
        if !sub || !sub.manually_unlocked
          locked = {:asset_string => self.asset_string, :unlock_at => self.unlock_at}
        end
      elsif (self.lock_at && self.lock_at <= Time.now)
        sub = user && quiz_submissions.find_by_user_id(user.id)
        if !sub || !sub.manually_unlocked
          locked = {:asset_string => self.asset_string, :lock_at => self.lock_at}
        end
      elsif (self.for_assignment? && l = self.assignment.locked_for?(user, opts))
        sub = user && quiz_submissions.find_by_user_id(user.id)
        if !sub || !sub.manually_unlocked
          locked = l
        end
      elsif (self.context_module_tag && !self.context_module_tag.available_for?(user, opts[:deep_check_if_needed]))
        sub = user && quiz_submissions.find_by_user_id(user.id)
        if !sub || !sub.manually_unlocked
          locked = {:asset_string => self.asset_string, :context_module => self.context_module_tag.context_module.attributes}
        end
      end
      locked
    end
  end
  
  def context_module_action(user, action, points=nil)
    self.context_module_tag.context_module_action(user, action, points) if self.context_module_tag
    self.assignment.context_module_tag.context_module_action(user, action, points) if self.assignment && self.assignment.context_module_tag
  end

  # virtual attribute
  def locked=(new_val)
    new_val = ActiveRecord::ConnectionAdapters::Column.value_to_boolean(new_val)
    if new_val
      #lock the quiz either until unlock_at, or indefinitely if unlock_at.nil?
      self.lock_at = Time.now
      self.unlock_at = [self.lock_at, self.unlock_at].min if self.unlock_at
    else
      # unlock the quiz
      self.unlock_at = Time.now
    end
  end

  def locked?
    (self.unlock_at && self.unlock_at > Time.now) ||
    (self.lock_at && self.lock_at <= Time.now)
  end

  def hide_results=(val)
    if(val.is_a?(Hash))
      if val[:last_attempt] == '1'
        val = 'until_after_last_attempt'
      elsif val[:never] != '1'
        val = 'always'
      else
        val = nil
      end
    end
    write_attribute(:hide_results, val)
  end
  
  def check_if_submissions_need_review
    self.quiz_submissions.each{|s| s.update_if_needs_review(self) }
  end
  
  def changed_significantly_since?(version_number)
    @significant_version ||= {}
    return @significant_version[version_number] if @significant_version[version_number]
    old_version = self.versions.get(version_number).model
    
    needs_review = false
    needs_review = true if old_version.points_possible != self.points_possible
    needs_review = true if (old_version.quiz_data || []).length != (self.quiz_data || []).length
    if !needs_review
      new_data = self.quiz_data
      old_data = old_version.quiz_data
      new_data.each_with_index do |q, i|
        needs_review = true if (q[:id] || q['id']) != (old_data[i][:id] || old_data[i]['id'])
      end
    end    
    @significant_version[version_number] = needs_review
  end
  
  def migrate_content_links_by_hand(user)
    self.quiz_questions.each do |question|
      data = QuizQuestion.migrate_question_hash(question.question_data, :context => self.context, :user => user)
      question.write_attribute(:question_data, data)
      question.save
    end
    data = self.quiz_data
    if data
      data.each_with_index do |obj, idx|
        if obj[:answers]
          data[idx] = QuizQuestion.migrate_question_hash(data[idx], :context => self.context, :user => user)
        elsif val.questions
          questions = []
          obj[:questions].each do |question|
            questions << QuizQuestion.migrate_question_hash(question, :context => self.context, :user => user)
          end
          obj[:questions] = questions
          data[idx] = obj
        end
      end
    end
    self.quiz_data = data
  end
  
  attr_accessor :clone_updated
  def clone_for(context, original_dup=nil, options={}, retrying = false)
    dup = original_dup
    if !self.cloned_item && !self.new_record?
      self.cloned_item ||= ClonedItem.create(:original_item => self)
      self.save!
    end
    existing = context.quizzes.active.find_by_id(self.id)
    existing ||= context.quizzes.active.find_by_cloned_item_id(self.cloned_item_id || 0)
    return existing if existing && !options[:overwrite]
    if (context.merge_mapped_id(self.assignment))
      dup ||= Quiz.find_by_assignment_id(context.merge_mapped_id(self.assignment))
    end
    dup ||= Quiz.new
    dup = existing if existing && options[:overwrite]
    self.attributes.delete_if{|k,v| [:id, :assignment_id, :assignment_group_id].include?(k.to_sym) }.each do |key, val|
      dup.send("#{key}=", val)
    end
    # We need to save the quiz now so that the migrate_question_hash call will find
    # the duplicated quiz and not try to make it itself.
    dup.context = context
    dup.saved_by = :assignment if options[:cloning_for_assignment]
    dup.save!
    data = self.quiz_data
    if data
      data.each_with_index do |obj, idx|
        if obj[:answers]
          data[idx] = QuizQuestion.migrate_question_hash(data[idx], :old_context => self.context, :new_context => context)
        elsif obj[:questions]
          questions = []
          obj[:questions].each do |question|
            questions << QuizQuestion.migrate_question_hash(question, :old_context => self.context, :new_context => context)
          end
          obj[:questions] = questions
          data[idx] = obj
        end
      end
    end
    dup.quiz_data = data
    dup.assignment_id = context.merge_mapped_id(self.assignment) rescue nil
    if !dup.assignment_id && self.assignment_id && self.assignment && !options[:cloning_for_assignment]
      new_assignment = self.assignment.clone_for(context, nil, :cloning_for_quiz => true)
      new_assignment.saved_by = :quiz
      new_assignment.save_without_broadcasting!
      context.map_merge(self.assignment, new_assignment)
      dup.assignment_id = new_assignment.id
    end
    begin
      dup.save!
    rescue => e
      logger.warn "Couldn't save quiz copy: #{e.to_s}"
      raise e if retrying
      return self.clone_for(context, original_dup, options, true)
    end
    entities = self.quiz_groups + self.quiz_questions
    entities.each do |entity|
      entity_dup = entity.clone_for(dup, nil, :old_context => self.context, :new_context => context)
      entity_dup.quiz_id = dup.id
      if entity_dup.respond_to?(:quiz_group_id=)
        entity_dup.quiz_group_id = context.merge_mapped_id(entity.quiz_group)
      end
      entity_dup.save!
      context.map_merge(entity, entity_dup)
    end
    dup.reload
    context.log_merge_result("Quiz \"#{self.title}\" created")
    context.may_have_links_to_migrate(dup)
    dup.updated_at = Time.now
    dup.clone_updated = true
    dup
  end
  
  def self.find_or_create_for_new_context(new_context, old_context, old_id)
    res = new_context.quizzes.active.find_by_cloned_item_id(old_context.quizzes.find_by_id(old_id).cloned_item_id || 0) rescue nil
    res = nil if res && !res.cloned_item_id
    if !res
      old = old_context.quizzes.active.find_by_id(old_id)
      res = old.clone_for(new_context) if old
      res.save if res
    end
    res
  end
  
  def statistics_csv(options={})
    options ||= {}
    columns = []
    columns << 'name' unless options[:anonymous]
    columns << 'id'
    columns << 'submitted'
    columns << 'attempt' if options[:include_all_versions]
    columns2 = [''] * columns.length
    first_question_index = columns.length
    submissions = self.quiz_submissions.scoped(:include => (options[:include_all_versions] ? [:versions] : [])).select{|s| s.completed? && s.submission_data.is_a?(Array) && self.context.students.map(&:id).include?(s.user_id) }
    if options[:include_all_versions]
      submissions = submissions.map(&:submitted_versions).flatten
    end
    submissions = submissions.sort_by(&:updated_at).reverse
    found_question_ids = {}
    quiz_datas = [quiz_data] + submissions.map(&:quiz_data)
    quiz_datas.each do |quiz_data|
      quiz_data.each do |question|
        if !found_question_ids[question[:id]]
          columns << "#{question[:id]}: #{strip_tags(question[:question_text])}"
          columns << question[:points_possible]
          columns2 << ''
          columns2 << ''
          found_question_ids[question[:id]] = true
        end
      end
    end
    last_question_index = columns.length - 1
    columns << 'n correct'
    columns << 'n incorrect'
    columns << 'score'
    columns2 << ''
    columns2 << ''
    columns2 << ''
    rows = []
    submissions.each do |submission|
      row = []
      row << submission.user.name unless options[:anonymous]
      row << submission.user_id
      row << submission.finished_at
      row << submission.attempt if options[:include_all_versions]
      columns[first_question_index..last_question_index].each do |id|
        next unless id.is_a?(String)
        id = id.to_i
        answer = submission.submission_data.detect{|a| a[:question_id] == id }
        question = submission.quiz_data.detect{|q| q[:id] == id}
        next unless question
        answer_item = question && question[:answers].detect{|a| a[:id].to_s == answer[:text] }
        answer_item ||= answer
        if question[:question_type] == 'fill_in_multiple_blanks_question'
          blank_ids = question[:answers].map{|a| a[:blank_id] }.uniq
          row << blank_ids.map{|blank_id| answer["answer_for_#{blank_id}".to_sym].gsub(/,/, '\,') }.join(',')
        elsif question[:question_type] == 'multiple_answers_question'
          row << question[:answers].map{|a| answer["answer_#{a[:id]}".to_sym] == '1' ? a[:text].gsub(/,/, '\,') : nil }.compact.join(',')
        elsif question[:question_type] == 'multiple_dropdowns_question'
          blank_ids = question[:answers].map{|a| a[:blank_id] }.uniq
          answer_ids = blank_ids.map{|blank_id| answer["answer_for_#{blank_id}".to_sym] }
          row << answer_ids.map{|id| (question[:answers].detect{|a| a[:id] == id } || {})[:text].try(:gsub, /,/, '\,' ) }.compact.join(',')
        elsif question[:question_type] == 'calculated_question'
          list = question[:answers][0][:variables].map{|a| [a[:name],a[:value].to_s].map{|str| str.gsub(/=>/, '\=>') }.join('=>') }
          list << answer[:text]
          row << list.map{|str| (str || '').gsub(/,/, '\,') }.join(',')
        elsif question[:question_type] == 'matching_question'
          answer_ids = question[:answers].map{|a| a[:id] }
          answer_and_matches = answer_ids.map{|id| [id, answer["answer_#{id}".to_sym].to_i] }
          row << answer_and_matches.map{|id, match_id| 
            res = []
            res << (question[:answers].detect{|a| a[:id] == id } || {})[:text]
            match = question[:matches].detect{|m| m[:match_id] == match_id } || question[:answers].detect{|m| m[:match_id] == match_id} || {}
            res << (match[:right] || match[:text])
            res.map{|s| (s || '').gsub(/=>/, '\=>')}.join('=>').gsub(/,/, '\,') 
          }.join(',')
        else
          row << ((answer_item && answer_item[:text]) || '')
        end
        row << (answer ? answer[:points] : "")
      end
      row << submission.submission_data.select{|a| a[:correct] }.length
      row << submission.submission_data.reject{|a| a[:correct] }.length
      row << submission.score
      rows << row
    end
    FasterCSV.generate do |csv|
      columns.each_with_index do |val, idx|
        r = []
        r << columns[idx]
        r << columns2[idx]
        rows.each do |row|
          r << row[idx]
        end
        csv << r
      end
    end
  end

  def statistics(include_all_versions=true)
    submissions = self.quiz_submissions.scoped(:include => (include_all_versions ? [:versions] : [])).select{|s| self.context.students.map(&:id).include?(s.user_id) }
    if include_all_versions
      submissions = submissions.map(&:submitted_versions).flatten
    end
    submissions = submissions.select{|s| s.completed? && s.submission_data.is_a?(Array) }
    submissions = submissions.sort_by(&:updated_at).reverse
    questions = (self.quiz_data || []).map{|q| q[:questions] ? q[:questions] : [q] }.flatten
    stats = {}
    found_ids = {}
    score_counter = Stats::Counter.new
    question_ids = []
    questions_hash = {}
    stats[:questions] = []
    stats[:multiple_attempts_exist] = submissions.any?{|s| s.attempt && s.attempt > 1 }
    stats[:multiple_attempts_included] = include_all_versions
    stats[:submission_user_ids] = []
    stats[:submission_count] = 0
    stats[:submission_score_tally] = 0
    stats[:submission_incorrect_tally] = 0
    stats[:unique_submission_count] = 0
    stats[:submission_correct_tally] = 0
    stats[:submission_duration_tally] = 0
    submissions.each do |sub|
      stats[:submission_count] += 1
      stats[:submission_user_ids] << sub.user_id if sub.user_id > 0
      if !found_ids[sub.id]
        stats[:unique_submission_count] += 1
        found_ids[sub.id] = true
      end
      answers = sub.submission_data || []
      next unless answers.is_a?(Array)
      points = answers.map{|a| a[:points] }.sum
      score_counter << points
      stats[:submission_score_tally] += points
      stats[:submission_score_max] = [stats[:submission_score_max] || 0, points].max
      stats[:submission_score_min] = [stats[:submission_score_min] || 0, points].min
      stats[:submission_incorrect_tally] += answers.select{|a| a[:correct] == false }.length
      stats[:submission_correct_tally] += answers.select{|a| a[:correct] == true }.length
      stats[:submission_duration_tally] += ((sub.finished_at - sub.started_at).to_i rescue 30)
      sub.quiz_data.each do |question|
        question_ids << question[:id]
        questions_hash[question[:id]] ||= question
      end
    end
    stats[:submission_score_average] = score_counter.mean.to_f rescue 0 #stats[:submission_count] > 0 ? stats[:submission_score_tally] / stats[:submission_count] : 0
    stats[:submission_score_high] = score_counter.max
    stats[:submission_score_low] = score_counter.min
    stats[:submission_duration_average] = stats[:submission_count] > 0 ? stats[:submission_duration_tally].to_f / stats[:submission_count].to_f : 0
    stats[:submission_score_stdev] = score_counter.standard_deviation rescue 0
    stats[:submission_incorrect_count_average] = stats[:submission_count] > 0 ? stats[:submission_incorrect_tally].to_f / stats[:submission_count].to_f : 0
    stats[:submission_correct_count_average] = stats[:submission_count] > 0 ? stats[:submission_correct_tally].to_f / stats[:submission_count].to_f : 0
    assessment_questions = AssessmentQuestion.find_all_by_id(question_ids).compact
    question_ids.uniq.each do |id|
      obj = questions.detect{|q| q[:answers] && q[:id] == id }
      if !obj && questions_hash[id]
        obj = questions_hash[id]
        aq_name = assessment_questions.detect{|q| q.id == obj[:assessment_question_id] }.try(:name)
        obj[:name] = aq_name || obj[:name]
      end
      if obj[:answers] && obj[:question_type] != 'text_only_question'
        stat = stats_for_question(obj, submissions)
        stats[:questions] << ['question', stat]
      end
    end
    stats[:last_submission_at] = submissions.map{|s| s.finished_at }.compact.max || self.created_at
    stats
  end
  
  def stats_for_question(question, submissions)
    res = question
    res[:responses] = 0
    res[:response_values] = []
    res[:unexpected_response_values] = []
    res[:user_ids] = []
    res[:answers] = question[:answers].map{|a| 
      answer = a
      answer[:responses] = 0
      answer[:user_ids] = []
      answer
    }
    res[:multiple_responses] = true if question[:question_type] == 'calculated_question'
    if question[:question_type] == 'numerical_question'
      res[:answers].each do |answer|
        if answer[:numerical_answer_type] == 'exact_answer'
          answer[:text] = "#{answer[:exact]} +/- #{answer[:margin]}"
        else
          answer[:text] = "#{answer[:start]} to #{answer[:end]}"
        end
      end
    end
    if question[:question_type] == 'matching_question'
      res[:multiple_responses] = true
      res[:answers].each_with_index do |answer, idx|
        res[:answers][idx][:answer_matches] = []
        (res[:matches] || res[:answers]).each do |right|
          match_answer = res[:answers].find{|a| a[:match_id].to_i == right[:match_id].to_i }
          match = {:responses => 0, :text => (right[:right] || right[:text]), :user_ids => [], :id => match_answer ? match_answer[:id] : right[:match_id] }
          res[:answers][idx][:answer_matches] << match
        end
      end
    elsif ['fill_in_multiple_blanks_question', 'multiple_dropdowns_question'].include?(question[:question_type])
      res[:multiple_responses] = true
      answer_keys = {}
      answers = []
      res[:answers].each_with_index do |answer, idx|
        if !answer_keys[answer[:blank_id]]
          answers << {:id => answer[:blank_id], :text => answer[:blank_id], :blank_id => answer[:blank_id], :answer_matches => [], :responses => 0, :user_ids => []}
          answer_keys[answer[:blank_id]] = answers.length - 1
        end
      end
      answers.each do |found_answer|
        res[:answers].select{|a| a[:blank_id] == found_answer[:blank_id] }.each do |sub_answer|
          correct = sub_answer[:weight] == 100
          match = {:responses => 0, :text => sub_answer[:text], :user_ids => [], :id => question[:question_type] == 'fill_in_multiple_blanks_question' ? found_answer[:blank_id] : sub_answer[:id], :correct => correct}
          found_answer[:answer_matches] << match
        end
      end
      res[:answer_sets] = answers
    end
    submissions.each do |submission|
      answers = submission.submission_data || []
      response = answers.select{|a| a[:question_id] == question[:id] }.first
      if response
        res[:responses] += 1
        res[:response_values] << response[:text]
        res[:user_ids] << submission.user_id
        if question[:question_type] == 'matching_question'
          res[:multiple_answers] = true
          res[:answers].each_with_index do |answer, idx|
            res[:answers][idx][:responses] += 1 if response[:correct]
            (res[:matches] || res[:answers]).each_with_index do |right, jdx|
              if response["answer_#{answer[:id]}".to_sym].to_i == right[:match_id]
                res[:answers][idx][:answer_matches][jdx][:responses] += 1
                res[:answers][idx][:answer_matches][jdx][:user_ids] << submission.user_id
              end
            end
          end
        elsif question[:question_type] == 'fill_in_multiple_blanks_question'
          res[:multiple_answers] = true
          res[:answer_sets].each_with_index do |answer, idx|
            found = false
            response_hash_id = Digest::MD5.hexdigest(response["answer_for_#{answer[:blank_id]}".to_sym].strip) if !response["answer_for_#{answer[:blank_id]}".to_sym].try(:strip).blank?
            res[:answer_sets][idx][:responses] += 1 if response[:correct]
            res[:answer_sets][idx][:answer_matches].each_with_index do |right, jdx|
              if response["answer_for_#{answer[:blank_id]}".to_sym] == right[:text]
                found = true
                res[:answer_sets][idx][:answer_matches][jdx][:responses] += 1
                res[:answer_sets][idx][:answer_matches][jdx][:user_ids] << submission.user_id
              end
            end
            if !found
              if response_hash_id
                answer = {:id => response_hash_id, :responses => 1, :user_ids => [submission.user_id], :text => response["answer_for_#{answer[:blank_id]}".to_sym]}
                res[:answer_sets][idx][:answer_matches] << answer
              end
            end
          end
        elsif question[:question_type] == 'multiple_dropdowns_question'
          res[:multiple_answers] = true
          res[:answer_sets].each_with_index do |answer, idx|
            res[:answer_sets][idx][:responses] += 1 if response[:correct]
            res[:answer_sets][idx][:answer_matches].each_with_index do |right, jdx|
              if response["answer_id_for_#{answer[:blank_id]}".to_sym] == right[:id]
                res[:answer_sets][idx][:answer_matches][jdx][:responses] += 1
                res[:answer_sets][idx][:answer_matches][jdx][:user_ids] << submission.user_id
              end
            end
          end
        elsif question[:question_type] == 'multiple_answers_question'
          res[:answers].each_with_index do |answer, idx|
            if response["answer_#{answer[:id]}".to_sym] == '1'
              res[:answers][idx][:responses] += 1
              res[:answers][idx][:user_ids] << submission.user_id
            end
          end
        elsif question[:question_type] == 'calculated_question'
          found = false
          response_hash_id = Digest::MD5.hexdigest(response[:text].strip.to_f.to_s) if !response[:text].try(:strip).blank?
          res[:answers].each_with_index do |answer, idx|
            if res[:answers][idx][:id] == response[:answer_id] || res[:answers][idx][:id] == response_hash_id
              found = true
              res[:answers][idx][:numbers] ||= {}
              res[:answers][idx][:numbers][response[:text].to_f] ||= {:responses => 0, :user_ids => [], :correct => true}
              res[:answers][idx][:numbers][response[:text].to_f][:responses] += 1
              res[:answers][idx][:numbers][response[:text].to_f][:user_ids] << submission.user_id
              res[:answers][idx][:responses] += 1
              res[:answers][idx][:user_ids] << submission.user_id
            end
          end
          if !found
            if ['numerical_question', 'short_answer_question'].include?(question[:question_type]) && response_hash_id
              answer = {:id => response_hash_id, :responses => 1, :user_ids => [submission.user_id], :text => response[:text].to_f.to_s}
              res[:answers] << answer
            end
          end
        elsif question[:question_type] == 'text_only_question'
        elsif question[:question_type] == 'essay_question'
          res[:essay_responses] ||= []
          res[:essay_responses] << {:user_id => submission.user_id, :text => response[:text].strip}
        else
          found = false
          response_hash_id = Digest::MD5.hexdigest(response[:text].strip) if !response[:text].try(:strip).blank?
          res[:answers].each_with_index do |answer, idx|
            if answer[:id] == response[:answer_id] || answer[:id] == response_hash_id
              found = true
              res[:answers][idx][:responses] += 1
              res[:answers][idx][:user_ids] << submission.user_id
            end
          end
          if !found
            
            if ['numerical_question', 'short_answer_question'].include?(question[:question_type]) && response_hash_id
              answer = {:id => response_hash_id, :responses => 1, :user_ids => [submission.user_id], :text => response[:text]}
              res[:answers] << answer
            end
          end
        end
      end
    end
    none = {
      :responses => res[:responses] - res[:answers].map{|a| a[:responses] || 0}.sum,
      :id => "none",
      :weight => 0,
      :text => "No Answer",
      :user_ids => res[:user_ids] - res[:answers].map{|a| a[:user_ids] }.flatten
    } rescue nil
    res[:answers] << none if none && none[:responses] > 0
    res
  end
  
  def unpublished_changes?
    self.last_edited_at && self.published_at && self.last_edited_at > self.published_at
  end
  
  def self.process_migration(data, migration, question_data)
    assessments = data['assessments'] ? data['assessments']['assessments'] : []
    to_import = migration.to_import 'quizzes'
    assessments.each do |assessment|
      migration_id = assessment['migration_id'] || assessment['assessment_id']
      if migration_id && (!to_import || to_import[migration_id])
        Quiz.import_from_migration(assessment, migration.context, question_data)
      end
    end
  end 
  
  # Import a quiz from a hash.
  # It assumes that all the referenced questions are already in the database
  def self.import_from_migration(hash, context, question_data, item=nil)
    hash = hash.with_indifferent_access
    # there might not be an import id if it's just a text-only type...
    item ||= find_by_context_type_and_context_id_and_id(context.class.to_s, context.id, hash[:id]) if hash[:id]
    item ||= find_by_context_type_and_context_id_and_migration_id(context.class.to_s, context.id, hash[:migration_id]) if hash[:migration_id]
    return if item # We don't update existing quizzes from migrations because OpenObjects leak memory
    item ||= context.quizzes.new
    
    item.migration_id = hash[:migration_id]
    item.title = hash[:title]
    item.scoring_policy = hash[:which_attempt_to_keep] if hash[:which_attempt_to_keep]
    item.allowed_attempts = hash[:allowed_attempts] if hash[:allowed_attempts]
    item.time_limit = hash[:time_limit] if hash[:time_limit]
    item.shuffle_answers = hash[:shuffle_answers] unless hash[:shuffle_answers].nil?
    item.show_correct_answers = hash[:show_correct_answers] unless hash[:show_correct_answers].nil?
    item.points_possible = hash[:points_possible] if hash[:points_possible]
    timestamp = hash[:due_date]
    if hash[:quiz_type] =~ /assignment/i && !item.assignment
      # The actual assignment will be created when the quiz is published
      item.quiz_type = 'assignment'
      if grading = hash[:grading]
        if grading[:assignment_group_migration_id]
          assignment_group = context.assignment_groups.find_by_migration_id(grading[:assignment_group_migration_id])
          item.assignment_group_id = assignment_group.id if assignment_group 
        end
        timestamp ||= grading[:due_date]
      end
    end
    timestamp = timestamp.to_i rescue 0
    item.due_at = Time.at(timestamp / 1000) if timestamp > 0
    item.save!
    if hash[:questions] && (!item.question_count || item.question_count == 0)
      count = 0
      hash[:questions].each do |q|
        if q['pick_count']
          count += q['pick_count'].to_i rescue 1
        else
          count += 1
        end
      end
      Quiz.update_all({:question_count=>count, :unpublished_question_count=>count}, "id=#{item.id}")
    end

    if item.quiz_questions.count == 0 && question_data
      hash[:questions] ||= []
      hash[:questions].each do |question|
        case question[:question_type]
          when "question_reference"
            if aq = question_data[question[:migration_id]]
              aq[:points_possible] = question[:points_possible] if question[:points_possible]
              QuizQuestion.import_from_migration(aq, context, item)
            else
              #TODO: no assessment question was imported for this question...
            end
          when "question_group"
            QuizGroup.import_from_migration(question, context, item, question_data)
          when "text_only_question"
            qq = item.quiz_questions.new
            qq.question_data = question
            qq.save!
        end
      end
    end

    context.imported_migration_items << item if context.imported_migration_items
    item
  end
  
  def self.serialization_excludes; [:access_code]; end

  set_policy do
    given { |user, session| self.cached_context_grants_right?(user, session, :manage_assignments) }#admins.include? user }
    set { can :manage and can :read and can :update and can :delete and can :create and can :submit }
    
    given { |user, session| self.cached_context_grants_right?(user, session, :manage_grades) }#admins.include? user }
    set { can :manage and can :read and can :update and can :delete and can :create and can :submit and can :grade }
    
    given { |user| self.available? && self.context.try_rescue(:is_public) && !self.graded? }
    set { can :submit }
    
    given { |user, session| self.cached_context_grants_right?(user, session, :read) }#students.include?(user) }
    set { can :read }

    given { |user, session| self.available? && self.cached_context_grants_right?(user, session, :participate_as_student) }#students.include?(user) }
    set { can :read and can :submit }
  end
  named_scope :include_assignment, lambda{
    { :include => :assignment }
  }
  named_scope :before, lambda{|date|
    {:conditions => ['quizzes.created_at < ?', date]}
  }
  named_scope :active, lambda{
    {:conditions => ['quizzes.workflow_state != ?', 'deleted'] }
  }
  named_scope :not_for_assignment, lambda{
    {:conditions => ['quizzes.assignment_id IS NULL'] }
  }
end
