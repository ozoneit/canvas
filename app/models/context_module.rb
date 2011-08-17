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

class ContextModule < ActiveRecord::Base
  include Workflow
  attr_accessible :context, :name, :unlock_at, :require_sequential_progress, :completion_requirements, :prerequisites
  belongs_to :context, :polymorphic => true
  belongs_to :cloned_item
  has_many :context_module_progressions, :dependent => :destroy
  has_many :content_tags, :dependent => :destroy, :order => 'content_tags.position, content_tags.title'
  adheres_to_policy
  acts_as_list :scope => :context
  
  serialize :prerequisites
  serialize :completion_requirements
  serialize :downstream_modules
  before_save :infer_position
  before_save :confirm_valid_requirements
  after_save :check_students
  after_save :touch_context
  
  def self.module_positions(context)
    # Keep a cached hash of all modules for a given context and their 
    # respective positions -- used when enforcing valid prerequisites
    # and when generating the list of downstream modules
    Rails.cache.fetch(['module_positions', context].cache_key) do
      hash = {}
      context.context_modules.active.each{|m| hash[m.id] = m.position || 0 }
      hash
    end
  end
  
  def infer_position
    @already_confirmed_valid_requirements = false
    prereqs = []
    (self.prerequisites || []).each do |pre|
      if pre[:type] == 'context_module'
        position = ContextModule.module_positions(self.context)[pre[:id].to_i] || 0 #self.context.context_modules.active.find_by_id(pre[:id])
        prereqs << pre if position && position < (self.position || 0)
      else
        prereqs << pre
      end
    end
    self.prerequisites = prereqs
    @re_evaluate_students = self.changed? || self.prerequisites_changed? || self.completion_requirements_changed?
    @update_downstrea_modules = self.prerequisites_changed? || self.completion_requirements_changed?
    self.position
  end
  
  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    self.deleted_at = Time.now
    ContentTag.update_all({:workflow_state => 'deleted', :updated_at => Time.now}, {:context_module_id => self.id})
    self.send_later_if_production(:update_downstreams, self.position)
    save!
    true
  end
  
  def restore
    self.workflow_state = 'active'
    self.save
  end
  
  def update_downstreams(original_position=nil)
    original_position ||= self.position || 0
    positions = ContextModule.module_positions(self.context).to_a.sort_by{|a| a[1] }
    downstream_ids = positions.select{|a| a[1] > (self.position || 0)}.map{|a| a[0] }
    downstreams = self.context.context_modules.active.find_all_by_id(downstream_ids)
    downstreams.each {|m| m.save_without_touching_context }
  end
  
  workflow do
    state :active
    state :deleted
  end
  
  named_scope :active, lambda{
    {:conditions => ['context_modules.workflow_state != ?', 'deleted'] }
  }
  named_scope :include_tags_and_progressions, lambda{
    {:include => [:content_tags, :context_module_progressions]}
  }
  
  def check_students
    return if @dont_check_students || self.deleted?
    # modules are ordered by position, so running through them in order will automatically
    # issues with dependencies loading in the correct order
    if @re_evaluate_students || true
      send_later_if_production :update_student_progressions
    end
    true
  end
  
  def update_student_progressions(user=nil)
    modules = ContextModule.find(:all, :conditions => {:context_type => self.context_type, :context_id => self.context_id}, :order => :position)
    students = user ? [user] : self.context.students
    modules.each do |mod|
      mod.re_evaluate_for(students, true)
    end
  end
  
  set_policy do
    given {|user, session| self.cached_context_grants_right?(user, session, :manage_content) }
    set { can :read and can :create and can :update and can :delete }
    
    given {|user, session| self.cached_context_grants_right?(user, session, :read) }
    set { can :read }
  end
  
  def available_for?(user, tag=nil, deep_check=false)
    return true if !self.to_be_unlocked && (!self.prerequisites || self.prerequisites.empty?) && !self.require_sequential_progress
    return true if self.grants_right?(user, nil, :update)
    progression = self.evaluate_for(user)
    res = progression && !progression.locked?
    if tag && tag.context_module_id == self.id && self.require_sequential_progress
      res = progression && progression.current_position && progression.current_position >= tag.position
    end
    if !res && deep_check
      progression = self.evaluate_for(user, true, true)
      if tag && tag.context_module_id == self.id && self.require_sequential_progress
        res = progression && progression.current_position && progression.current_position >= tag.position
      end
    end
    res
  end
  
  def current?
    (self.start_at || self.end_at) && (!self.start_at || Time.now >= self.start_at) && (!self.end_at || Time.now <= self.end_at) rescue true
  end
  
  def self.context_prerequisites(context)
    prereq = {}
    to_visit = []
    visited = []
    context.context_modules.active.each do |m|
      prereq[m.id] = []
      (m.prerequisites || []).each do |p|
        prereq[m.id] << p
        to_visit << [m.id, p[:id]] if p[:type] == 'context_module'
      end
    end
    while !to_visit.empty?
      val = to_visit.shift
      if(!visited.include?(val))
        visited << val
        (prereq[val[1]] || []).each do |p|
          prereq[val[0]] << p
          to_visit << [val[0], p[:context_module_id]] if p[:type] == 'context_module'
        end
      end
    end
    prereq.each{|idx, val| prereq[idx] = val.uniq.compact }
    prereq
  end
  
  def prerequisites=(val)
    if val.is_a?(Array)
      val = val.map {|item|
        if item[:type] == 'context_module'
          "module_#{item[:id]}"
        else
          "#{item[:type]}_#{item[:id]}"
        end
      }.join(',') rescue nil
    end
    if val.is_a?(String)
      res = []
      modules = self.context.context_modules.active
      module_prereqs = ContextModule.context_prerequisites(self.context)
      invalid_prereqs = module_prereqs.to_a.map{|id, ps| id if (ps.any?{|p| p[:type] == 'context_module' && p[:id].to_i == self.id}) }.compact
      pres = val.split(",")
      pres.each do |pre|
        type, id = pre.reverse.split("_", 2).map{|s| s.reverse}.reverse
        m = modules.to_a.find{|m| m.id == id.to_i}
        if type == 'module' && !invalid_prereqs.include?(id.to_i) && m
          res << {:id => id.to_i, :type => 'context_module', :name => (modules.to_a.find{|m| m.id == id.to_i}.name rescue "module")}
        end
      end
      val = res
    else
      val = nil
    end
    write_attribute(:prerequisites, val)
  end
  
  def completion_requirements=(val)
    if val.is_a?(Array)
      hash = {}
      val.each{|i| hash[i[:id]] = i }
      val = hash
    end
    if val.is_a?(Hash)
      res = []
      tag_ids = self.content_tags.active.map{|t| t.id}
      val.each do |id, opts|
        if tag_ids.include?(id.to_i)
          res << {:id => id.to_i, :type => opts[:type], :min_score => opts[:min_score], :max_score => opts[:max_score]} #id => id.to_i, :type => type
        end
      end
      val = res
    else
      val = nil
    end
    write_attribute(:completion_requirements, val)
  end

  def add_item(params, added_item=nil)
    association_id = nil
    position = (self.content_tags.active.map(&:position).compact.max || 0) + 1
    if params[:type] == "wiki_page"
      item = WikiPage.find(params[:id]) rescue nil
      item_namespace = item.wiki.wiki_namespaces.find_by_context_id_and_context_type(self.context_id, self.context_type)
      item = nil unless item && item_namespace
      association_id = item_namespace.id rescue nil
    elsif params[:type] == "attachment"
      item = self.context.attachments.active.find(params[:id]) rescue nil
    elsif params[:type] == "assignment"
      item = self.context.assignments.active.find(params[:id]) rescue nil
    elsif params[:type] == "discussion_topic"
      item = self.context.discussion_topics.active.find(params[:id]) rescue nil
    elsif params[:type] == "quiz"
      item = self.context.quizzes.active.find(params[:id]) rescue nil
    end
    if params[:type] == 'external_url'
      title = params[:title]
      added_item ||= self.content_tags.build(
        :context_id => self.context_id, 
        :context_type => self.context_type
      )
      added_item.attributes = {
        :content_id => 0, 
        :content_type => 'ExternalUrl', 
        :url => params[:url], 
        :tag_type => 'context_module', 
        :title => title, 
        :indent => params[:indent], 
        :position => position
      }
      added_item.context_module_id = self.id
      added_item.indent = params[:indent] || 0
      added_item.workflow_state = 'active'
      added_item.save
      added_item
    elsif params[:type] == 'context_external_tool'
      title = params[:title]
      added_item ||= self.content_tags.build(
        :context_id => self.context_id, 
        :context_type => self.context_type
      )
      tool = ContextExternalTool.find_external_tool(params[:url], self.context)
      added_item.attributes = {
        :content_id => tool ? tool.id : 0, 
        :content_type => 'ContextExternalTool', 
        :url => params[:url], 
        :tag_type => 'context_module', 
        :title => title, 
        :indent => params[:indent], 
        :position => position
      }
      added_item.context_module_id = self.id
      added_item.indent = params[:indent] || 0
      added_item.workflow_state = 'active'
      added_item.save
      added_item
    elsif params[:type] == 'context_module_sub_header'
      title = params[:title]
      added_item ||= self.content_tags.build(
        :context_id => self.context_id, 
        :context_type => self.context_type
      )
      added_item.attributes = {
        :content_id => 0, 
        :content_type => 'ContextModuleSubHeader', 
        :tag_type => 'context_module', 
        :title => title, 
        :indent => params[:indent], 
        :position => position
      }
      added_item.context_module_id = self.id
      added_item.indent = params[:indent] || 0
      added_item.workflow_state = 'active'
      added_item.save
      added_item
    else
      return nil unless item
      added_item ||= ContentTag.find_by_content_id_and_content_type_and_context_id_and_context_type_and_tag_type(item.id, item.class.to_s, self.context_id, self.context_type, 'context_module')
      title = params[:title] || (item.title rescue item.name)
      added_item ||= self.content_tags.build(
        :context_id => self.context_id, 
        :context_type => self.context_type
      )
      added_item.attributes = {
        :content_id => item.id, 
        :content_type => item.class.to_s, 
        :tag_type => 'context_module', 
        :title => title, 
        :indent => params[:indent], 
        :position => position
      }
      added_item.context_module_id = self.id
      added_item.context_module_association_id = association_id
      added_item.indent = params[:indent] || 0
      added_item.workflow_state = 'active'
      added_item.save
      added_item
    end
  end
  
  def update_for(user, action, tag, points=nil)
    return nil unless self.context.users.include?(user)
    return nil unless self.prerequisites_satisfied?(user)
    progression = self.find_or_create_progression(user)
    progression.requirements_met ||= []
    requirement = self.completion_requirements.to_a.find{|p| p[:id] == tag.id}
    return if !requirement || progression.requirements_met.include?(requirement)
    met = false
    met = true if requirement[:type] == 'must_view' && (action == :read || action == :contributed)
    met = true if requirement[:type] == 'must_contribute' && action == :contributed
    met = true if requirement[:type] == 'must_submit' && action == :scored
    met = true if requirement[:type] == 'must_submit' && action == :submitted
    met = true if requirement[:type] == 'min_score' && action == :scored && points && points >= requirement[:min_score].to_f
    met = true if requirement[:type] == 'max_score' && action == :scored && points && points <= requirement[:max_score].to_f
    if met
      progression.requirements_met << requirement
    end
    progression.save!
    User.module_progression_job_queued(user.id)
    send_later_if_production :update_student_progressions, user
    progression
  end
  
  def self.requirement_description(req)
    case req[:type]
    when 'must_view'
      "must view the page"
    when 'must_contribute'
      "must contribute to the page"
    when 'must_submit'
      "must submit the assignment"
    when 'min_score'
      "must score at least a #{req[:min_score]}"
    when 'max_score'
      "must score no more than a #{req[:max_score]}"
    else
      nil
    end
  end
  
  def prerequisites_satisfied?(user, recursive_check=false)
    unlocked = (self.prerequisites || []).all? do |pre|
      if pre[:type] == 'context_module'
        prog = user.module_progression_for(pre[:id])
        if !prog
          prereq = self.context.context_modules.active.find_by_id(pre[:id]) if !prog
          prog = prereq.evaluate_for(user, true) if prereq
        end
        prog.completed? rescue false
      elsif pre[:type] == 'min_score'
      elsif pre[:type] == 'max_score'
      elsif pre[:type] == 'must_contribute'
      elsif pre[:type] == 'must_submit'
      elsif pre[:type] == 'must_view'
      else
        true
      end
    end
    unlocked
  end
  
  def clear_cached_lookups
    @cached_progressions = nil
    @cached_tags = nil
  end
  
  def re_evaluate_for(users, skip_confirm_valid_requirements=false)
    users = Array(users)
    users.each{|u| u.clear_cached_lookups }
    progressions = self.find_or_create_progressions(users)
    progressions.each{|p| p.workflow_state = 'locked' }
    @already_confirmed_valid_requirements = true if skip_confirm_valid_requirements
    progressions.each do |progression|
      self.evaluate_for(progression, true, true)
    end
  end
  
  def confirm_valid_requirements(do_save=false)
    return if @already_confirmed_valid_requirements
    @already_confirmed_valid_requirements = true
    tags = self.content_tags.active
    new_reqs = []
    changed = false
    (self.completion_requirements || []).each do |req|
      added = false
      if !req[:id]
        
      elsif req[:type] == 'must_view'
        new_reqs << req if tags.any?{|t| t.id == req[:id].to_i }
        added = true
      elsif req[:type] == 'must_contribute'
        new_reqs << req if tags.any?{|t| t.id == req[:id].to_i }
        added = true
      elsif req[:type] == 'must_submit' || req[:type] == 'min_score' || req[:type] == 'max_score'
        tag = tags.detect{|t| t.id == req[:id].to_i }
        new_reqs << req if tag && tag.scoreable?
        added = true
      end
      changed = true if !added
    end
    self.completion_requirements = new_reqs
    @dont_check_students = true
    self.save if do_save && changed
    new_reqs
  end
  
  def find_or_create_progressions(users)
    users = Array(users)
    users_hash = {}
    users.each{|u| users_hash[u.id] = u }
    @cached_progressions ||= self.context_module_progressions
    progressions = @cached_progressions.select{|p| users_hash[p.user_id] } #self.context_module_progressions.find_all_by_user_id(users.map(&:id))
    progressions_hash = {}
    progressions.each{|p| progressions_hash[p.user_id] = p }
    newbies = users.select{|u| !progressions_hash[u.id] }
    progressions += newbies.map{|u| find_or_create_progression(u) }
    progressions.each{|p| p.user = users_hash[p.user_id] }
    progressions.uniq
  end
  
  def find_or_create_progression(user)
    return nil unless user
    ContextModule.find_or_create_progression(self.id, user.id)
  end
  
  def find_or_create_progression_with_multiple_lookups(user)
    user.module_progression_for(self.id) || self.find_or_create_progression(user)
  end
  
  def self.find_or_create_progression(module_id, user_id)
    s = nil
    attempts = 0
    begin
      s = ContextModuleProgression.find_or_initialize_by_context_module_id_and_user_id(module_id, user_id)
      s.save! if s.new_record?
      raise "bad" if s.new_record?
    rescue => e
      attempts += 1
      retry if attempts < 3
    end
    s
  end
  
  def content_tags_hash
    return @tags_hash if @tags_hash
    @tags_hash = {}
    self.content_tags.each{|t| @tags_hash[t.id] = t }
    @tags_hash
  end
  
  def evaluate_for(user, recursive_check=false, deep_check=false)
    progression = nil
    if user.is_a?(ContextModuleProgression)
      progression = user
      user = progression.user
    end
    return nil unless user
    progression ||= self.find_or_create_progression_with_multiple_lookups(user)
    requirements_met_changed = false
    if User.module_progression_jobs_queued?(user.id)
      progression.workflow_state = 'locked'
    end
    if deep_check
      confirm_valid_requirements(true) rescue nil
    end
    @cached_tags ||= self.content_tags.active
    tags = @cached_tags
    if !recursive_check && !progression.new_record? && progression.updated_at > self.updated_at + 1 && ENV['RAILS_ENV'] != 'test' && !User.module_progression_jobs_queued?(user.id)
    else
      if (self.completion_requirements || []).empty? && (self.prerequisites || []).empty?
        progression.workflow_state = 'completed'
        progression.save
      end
      progression.workflow_state = 'locked'
      if self.to_be_unlocked
        progression.workflow_state = 'locked'
      else
        progression.requirements_met ||= []
        if progression.locked?
          progression.workflow_state = 'unlocked' if self.prerequisites_satisfied?(user, recursive_check)
        end
        if progression.unlocked? || progression.started?
          orig_reqs = (progression.requirements_met || []).map{|r| "#{r[:id]}_#{r[:type]}" }.sort
          completes = (self.completion_requirements || []).map do |req|
            tag = tags.detect{|t| t.id == req[:id].to_i} #ContentTag.find_by_id(req[:id])
            if !tag
              res = true
            elsif ['min_score', 'max_score', 'must_submit'].include?(req[:type]) && !tag.scoreable?
              res = true
            else
              progression.deep_evaluate(self) if deep_check
              res = progression.requirements_met.any?{|r| r[:id] == req[:id] && r[:type] == req[:type] } #include?(req)
              if req[:type] == 'min_score'
                progression.requirements_met = progression.requirements_met.select{|r| r[:id] != req[:id] || r[:type] != req[:type]}
                if tag.content_type == "Quiz"
                  submission = QuizSubmission.find_by_quiz_id_and_user_id(tag.content_id, user.id)
                else
                  submission = Submission.find_by_assignment_id_and_user_id(tag.content_id, user.id)
                end
                if submission && submission.score && submission.score >= req[:min_score].to_f
                  progression.requirements_met << req
                  res = true
                else
                  res = false
                end
              end
            end
            res
          end
          new_reqs = (progression.requirements_met || []).map{|r| "#{r[:id]}_#{r[:type]}" }.sort
          requirements_met_changed = new_reqs != orig_reqs
          progression.workflow_state = 'started' if completes.any?
          progression.workflow_state = 'completed' if completes.all?
        end
      end
    end
    position = nil
    found_failure = false
    if self.require_sequential_progress
      tags.each do |tag|
        requirements_for_tag = (self.completion_requirements || []).select{|r| r[:id] == tag.id }.sort_by{|r| r[:id]}
        next if found_failure
        if requirements_for_tag.empty?
          position = tag.position
        else
          all_met = requirements_for_tag.all? do |req|
            (progression.requirements_met || []).any?{|r| r[:id] == req[:id] && r[:type] == req[:type] }
          end
          if all_met
            position = tag.position if tag.position && all_met
          else
            position = tag.position
            found_failure = true
          end
        end
      end
    end
    progression.current_position = position
    progression.save if progression.workflow_state_changed? || requirements_met_changed
    progression
  end
  
  def self.fast_cached_for_context(context)
    hashes = Rails.cache.fetch(['fast_modules_for', context].cache_key) do
      context.context_modules.active.map{|m| {:id => m.id, :name => m.name} }
    end
    OpenObject.process(hashes)
  end
  
  def self.visible_module_item_count
    75
  end
  
  def to_be_unlocked
    self.unlock_at && self.unlock_at > Time.now
  end
  
  def has_prerequisites?
    self.prerequisites && !self.prerequisites.empty?
  end
  
  attr_accessor :clone_updated
  def clone_for(context, dup=nil, options={})
    options[:migrate] = true if options[:migrate] == nil
    if !self.cloned_item && !self.new_record?
      self.cloned_item ||= ClonedItem.create(:original_item => self)
      self.save! 
    end
    existing = context.context_modules.active.find_by_id(self.id)
    existing ||= context.context_modules.active.find_by_cloned_item_id(self.cloned_item_id || 0)
    return existing if existing && !options[:overwrite]
    dup ||= ContextModule.new
    dup = existing if existing && options[:overwrite]

    dup.context = context
    self.attributes.delete_if{|k,v| [:id, :context_id, :context_type, :downstream_modules].include?(k.to_sym) }.each do |key, val|
      dup.send("#{key}=", val)
    end

    dup.save!
    tag_changes = {}
    self.content_tags.active.each do |tag|
      new_tag = tag.clone_for(context, nil, :context_module_id => dup.id)
      if new_tag
        new_tag.context_module_id = dup.id
        new_tag.save
        context.map_merge(tag, new_tag)
        tag_changes[tag.id] = new_tag.id
      end
    end
    pres = []
    (self.prerequisites || []).each do |req|
      new_req = req.dup
      if req[:type] == 'context_module'
        id = context.merge_mapped_id("context_module_#{req[:id]}")
        if !id
          cm = self.context.context_modules.find_by_id(req[:id])
          clone_id = cm.cloned_item_id if cm
          obj = ContextModule.find_by_cloned_item_id_and_context_id_and_context_type(clone_id, context.id, context.class.to_s) if clone_id
          id = obj.id if obj
        end
        new_req[:id] = id
        new_req = nil unless id
      end
      pres << new_req if new_req
    end
    dup.prerequisites = pres
    reqs = []
    (self.completion_requirements || []).each do |req|
      new_req = req.dup
      new_req[:id] = tag_changes[req[:id]]
      reqs << new_req
    end
    dup.completion_requirements = reqs
    context.log_merge_result("Module \"#{self.name}\" created")
    dup.updated_at = Time.now
    dup.clone_updated = true
    dup
  end

  def self.process_migration(data, migration)
    modules = data['modules'] ? data['modules'] : []
    to_import = migration.to_import 'modules'
    modules.each do |mod|
      if mod['migration_id'] && (!to_import || to_import[mod['migration_id']])
        import_from_migration(mod, migration.context)
      end
    end
    migration_ids = modules.map{|m| m['module_id'] }.compact
    conn = ActiveRecord::Base.connection
    cases = []
    max = migration.context.context_modules.map(&:position).compact.max || 0
    modules.each_with_index{|m, idx| cases << " WHEN migration_id=#{conn.quote(m['module_id'])} THEN #{max + idx + 1} " if m['module_id'] }
    unless cases.empty?
      conn.execute("UPDATE context_modules SET position=CASE #{cases.join(' ')} ELSE NULL END WHERE context_id=#{migration.context.id} AND context_type=#{conn.quote(migration.context.class.to_s)} AND migration_id IN (#{migration_ids.map{|id| conn.quote(id)}.join(',')})")
    end
  end
  
  def self.import_from_migration(hash, context, item=nil)
    hash = hash.with_indifferent_access
    return nil if hash[:migration_id] && hash[:modules_to_import] && !hash[:modules_to_import][hash[:migration_id]]
    item ||= find_by_context_type_and_context_id_and_id(context.class.to_s, context.id, hash[:id])
    item ||= find_by_context_type_and_context_id_and_migration_id(context.class.to_s, context.id, hash[:migration_id]) if hash[:migration_id]
    item ||= new(:context => context)
    item.name = hash[:title] || hash[:description]
    context.imported_migration_items << item if context.imported_migration_items && item.new_record?
    item.migration_id = hash[:migration_id]
    item.position = hash[:order]
    item.context = context
    item.save!
    @item_migration_position = item.content_tags.active.map(&:position).compact.max || 0
    (hash[:items] || []).each do |tag_hash|
      item.add_item_from_migration(tag_hash, 0, context)
    end
    context.imported_migration_items << item
    item
  end
  
  def add_item_from_migration(hash, level, context)
    hash = hash.with_indifferent_access
    hash[:migration_id] ||= hash[:linked_resource_id] 
    hash[:migration_id] ||= Digest::MD5.hexdigest(hash[:title]) if hash[:title]
    item = nil
    existing_item = content_tags.find_by_id(hash[:id])
    existing_item ||= content_tags.find_by_migration_id(hash[:migration_id]) if hash[:migration_id]
    existing_item ||= content_tags.new(:context => context)
    context.imported_migration_items << existing_item if context.imported_migration_items && existing_item.new_record?
    existing_item.migration_id = hash[:migration_id]
    hash[:indents] = [hash[:indents] || 0, level].max
    if hash[:linked_resource_type] =~ /wiki_type/i
      wiki = self.context.wiki.wiki_pages.find_by_migration_id(hash[:migration_id]) if hash[:migration_id]
      if wiki
        item = self.add_item({
          :title => hash[:title] || hash[:linked_resource_title],
          :type => 'wiki_page',
          :id => wiki.id,
          :indent => hash[:indents].to_i
        }, existing_item)
      end
    elsif ['PAGE_TYPE', 'FILE_TYPE'].member? hash[:linked_resource_type]
      # this is a file of some kind
      file = self.context.attachments.find_by_migration_id(hash[:migration_id]) if hash[:migration_id]
      if file
        item = self.add_item({
          :title => hash[:title] || hash[:linked_resource_title],
          :type => 'attachment',
          :id => file.id,
          :indent => hash[:indents].to_i
        }, existing_item)
      end
    elsif ['ASSIGNMENT_TYPE', 'PROJECT_TYPE'].member? hash[:linked_resource_type]
      # this is a file of some kind
      ass = self.context.assignments.find_by_migration_id(hash[:migration_id]) if hash[:migration_id]
      if ass
        item = self.add_item({
          :title => hash[:title] || hash[:linked_resource_title],
          :type => 'assignment',
          :id => ass.id,
          :indent => hash[:indents].to_i
        }, existing_item)
      end
    elsif ['FOLDER_TYPE', 'HEADING'].member?(hash[:linked_resource_type] || hash[:type])
      # just a snippet of text
      item = self.add_item({
        :title => hash[:title] || hash[:linked_resource_title],
        :type => 'context_module_sub_header',
        :indent => hash[:indents].to_i
      }, existing_item)
    elsif hash[:linked_resource_type] == 'URL_TYPE'
      # external url
      if hash['url']
        item = self.add_item({
          :title => hash[:title] || hash[:linked_resource_title] || hash['description'],
          :type => 'external_url',
          :indent => hash[:indents].to_i,
          :url => hash['url']
        }, existing_item)
      end
    elsif hash[:linked_resource_type] == 'ASSESSMENT_TYPE'
      quiz = self.context.quizzes.find_by_migration_id(hash[:migration_id]) if hash[:migration_id]
      if quiz
        item = self.add_item({
          :title => hash[:title] || hash[:linked_resource_title],
          :type => 'quiz',
          :indent => hash[:indents].to_i,
          :id => quiz.id
        }, existing_item)
      end
    elsif hash[:linked_resource_type] == 'DISCUSSION_TOPIC_TYPE'
      topic = self.context.discussion_topics.find_by_migration_id(hash[:migration_id]) if hash[:migration_id]
      if topic
        item = self.add_item({
          :title => hash[:title] || hash[:linked_resource_title],
          :type => 'discussion_topic',
          :indent => hash[:indents].to_i,
          :id => topic.id
        }, existing_item)
      end
    elsif hash[:linked_resource_type] == 'UNSUPPORTED_TYPE'
      # We know what this is and that we don't support it
    else
      # We don't know what this is
    end
    if item
      item.migration_id = hash[:migration_id]
      item.position = (@item_migration_position ||= self.content_tags.active.map(&:position).compact.max || 0)
      item.workflow_state = 'active'
      @item_migration_position += 1
      item.save!
    end
    if hash[:sub_items]
      hash[:sub_items].each do |tag_hash|
        self.add_item_from_migration(tag_hash, level + 1, context)
      end
    end
    item
  end
end
