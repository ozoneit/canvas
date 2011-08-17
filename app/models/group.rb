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

class Group < ActiveRecord::Base
  include Context
  include Workflow

  attr_accessible :name, :context, :max_membership, :category, :join_level, :default_view
  has_many :group_memberships, :dependent => :destroy, :conditions => ['group_memberships.workflow_state != ?', 'deleted']
  has_many :users, :through => :group_memberships, :conditions => ['users.workflow_state != ?', 'deleted']
  has_many :participating_group_memberships, :class_name => "GroupMembership", :conditions => ['group_memberships.workflow_state = ?', 'accepted']
  has_many :participating_users, :source => :user, :through => :participating_group_memberships
  has_many :invited_group_memberships, :class_name => "GroupMembership", :conditions => ['group_memberships.workflow_state = ?', 'invited']
  has_many :invited_users, :source => :user, :through => :invited_group_memberships
  belongs_to :context, :polymorphic => true
  belongs_to :account

  has_many :calendar_events, :as => :context, :dependent => :destroy
  has_many :discussion_topics, :as => :context, :conditions => ['discussion_topics.workflow_state != ?', 'deleted'], :include => :user, :dependent => :destroy, :order => 'discussion_topics.position DESC, discussion_topics.created_at DESC'
  has_many :active_discussion_topics, :as => :context, :class_name => 'DiscussionTopic', :conditions => ['discussion_topics.workflow_state != ?', 'deleted'], :include => :user
  has_many :all_discussion_topics, :as => :context, :class_name => "DiscussionTopic", :include => :user, :dependent => :destroy
  has_many :discussion_entries, :through => :discussion_topics, :include => [:discussion_topic, :user], :dependent => :destroy
  has_many :announcements, :as => :context, :class_name => 'Announcement', :dependent => :destroy
  has_many :active_announcements, :as => :context, :class_name => 'Announcement', :conditions => ['discussion_topics.workflow_state != ?', 'deleted']
  has_many :attachments, :as => :context, :dependent => :destroy
  has_many :active_attachments, :as => :context, :class_name => 'Attachment', :conditions => ['attachments.file_state != ?', 'deleted']
  has_many :active_assignments, :as => :context, :class_name => 'Assignment', :conditions => ['assignments.workflow_state != ?', 'deleted']
  has_many :all_attachments, :as => 'context', :class_name => 'Attachment'
  has_many :folders, :as => :context, :dependent => :destroy, :order => 'folders.name'
  has_many :active_folders, :class_name => 'Folder', :as => :context, :conditions => ['folders.workflow_state != ?', 'deleted'], :order => 'folders.name'
  has_many :active_folders_with_sub_folders, :class_name => 'Folder', :as => :context, :include => [:active_sub_folders], :conditions => ['folders.workflow_state != ?', 'deleted'], :order => 'folders.name'
  has_many :active_folders_detailed, :class_name => 'Folder', :as => :context, :include => [:active_sub_folders, :active_file_attachments], :conditions => ['folders.workflow_state != ?', 'deleted'], :order => 'folders.name'
  has_many :external_feeds, :as => :context, :dependent => :destroy
  has_many :messages, :as => :context, :dependent => :destroy
  belongs_to :wiki
  has_many :default_wiki_wiki_pages, :class_name => 'WikiPage', :through => :wiki, :source => :wiki_pages
  has_many :active_default_wiki_wiki_pages, :class_name => 'WikiPage', :through => :wiki, :source => :wiki_pages, :conditions => ['wiki_pages.workflow_state = ?', 'active']
  has_many :wiki_namespaces, :as => :context, :dependent => :destroy
  has_many :web_conferences, :as => :context, :dependent => :destroy
  has_many :tags, :class_name => 'ContentTag', :as => 'context', :order => 'LOWER(title)', :dependent => :destroy
  has_many :collaborations, :as => :context, :order => 'title, created_at', :dependent => :destroy
  has_one :scribd_account, :as => :scribdable
  has_many :short_message_associations, :as => :context, :include => :short_message, :dependent => :destroy
  has_many :short_messages, :through => :short_message_associations, :dependent => :destroy
  has_many :context_messages, :as => :context, :dependent => :destroy
  has_many :media_objects, :as => :context
  
  before_save :ensure_defaults
  after_save :close_memberships_if_deleted
  
  adheres_to_policy
  
  def wiki
    res = Wiki.find_by_id(self.wiki_id)
    unless res
      res = WikiNamespace.default_for_context(self).wiki
      self.wiki_id = res.id if res
      self.save
    end
    res
  end
  
  def auto_accept?(user)
    return false unless user
    (self.category == Group.student_organized_category && self.join_level == 'parent_context_auto_join' && self.context.users.include?(user))
  end
  
  def allow_join_request?(user)
    return false unless user
    (self.category == Group.student_organized_category && self.join_level == 'parent_context_auto_join' && self.context.users.include?(user)) ||
    (self.category == Group.student_organized_category && self.join_level == 'parent_context_request' && self.context.users.include?(user))
  end
  
  def participants
    participating_users.uniq
  end
  
  def context_code
    raise "DONT USE THIS, use .short_name instead" unless ENV['RAILS_ENV'] == "production"
  end
  
  def membership_for_user(user)
    self.group_memberships.find_by_user_id(user && user.id)
  end
  
  def short_name
    name
  end
  
  def self.find_all_by_context_code(codes)
    ids = codes.map{|c| c.match(/\Agroup_(\d+)\z/)[1] rescue nil }.compact
    Group.find(ids)
  end
  
  workflow do
    state :available do
      event :complete, :transitions_to => :completed
      event :close, :transitions_to => :closed
    end
    
    # Closed to new entrants
    state :closed do
      event :complete, :transitions_to => :completed
      event :open, :transitions_to => :available
    end
    
    state :completed
    state :deleted
  end
  
  def active?
    self.available? || self.closed?
  end

  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    self.deleted_at = Time.now
    self.save
  end
  
  def close_memberships_if_deleted
    return unless self.deleted?
    memberships = self.group_memberships
    User.update_all({:updated_at => Time.now}, {:id => memberships.map(&:user_id).uniq})
    GroupMembership.update_all({:workflow_state => 'deleted'}, {:id => memberships.map(&:id).uniq})
  end
  
  named_scope :active, :conditions => ['groups.workflow_state != ?', 'deleted']
  
  def full_name
    res = self.name
    res += ": #{(self.context.course_code rescue self.context.name)}" if self.context
  end

  
  def is_public
    false
  end
  
  def to_atom
    Atom::Entry.new do |entry|
      entry.title     = self.name
      entry.updated   = self.updated_at
      entry.published = self.created_at
      entry.links    << Atom::Link.new(:rel => 'alternate', 
                                    :href => "/groups/#{self.id}")
    end
  end
  
  named_scope :for_category, lambda{|category|
    {:conditions => {:category => category } }
  }
  
  def add_user(user)
    return nil if !user
    unless member = self.group_memberships.find_by_user_id(user.id)
      member = self.group_memberships.create(:user=>user)
    end
    return member
  end
  
  def invite_user(user)
    return nil if !user
    res = nil
    Group.transaction do
      res = self.group_memberships.find_or_initialize_by_user_id(user.id)
      res.workflow_state = 'invited' if res.new_record?
      res.save
    end
    res
  end
  
  def request_user(user)
    return nil if !user
    res = nil
    Group.transaction do
      res = self.group_memberships.find_or_initialize_by_user_id(user.id)
      res.workflow_state = 'requested' if res.new_record?
      res.save
    end
    res
  end
  
  def invitees=(params)
    invitees = []
    (params || {}).each do |key, val|
      if self.context
        invitees << self.context.users.find_by_id(key.to_i) if val != '0'
      else
        invitees << User.find_by_id(key.to_i) if val != '0'
      end
    end
    invitees.compact.map{|i| self.invite_user(i) }.compact
  end
  
  def peer_groups
    return [] if !self.context || self.category == Group.student_organized_category
    self.context.groups.find(:all, :conditions => ["category = ? and id != ?", self.category, self.id])
  end
  
  def migrate_content_links(html, from_course)
    Course.migrate_content_links(html, from_course, self)
  end
  
  attr_accessor :merge_mappings
  attr_accessor :merge_results
  def merge_mapped_id(*args)
    nil
  end
  
  def map_merge(*args)
  end
  def log_merge_result(text)
    @merge_results ||= []
    @merge_results << text
  end
  def warn_merge_result(text)
    record_merge_result(text)
  end

  
  def self.student_organized_category
    "Student Groups"
  end
  
  def ensure_defaults
    self.name ||= UUIDSingleton.instance.generate
    self.uuid ||= UUIDSingleton.instance.generate
    self.category ||= Group.student_organized_category
    self.join_level ||= 'invitation_only'
    if self.context && self.context.is_a?(Course)
      self.account = self.context.account if self.context
    elsif self.context && self.context.is_a?(Account)
      self.account = self.context
    end
  end
  private :ensure_defaults

  # if you modify this set_policy block, note that we've denormalized this
  # permission check for efficiency -- see User#cached_contexts
  set_policy do
    given { |user| user && self.participating_group_memberships.find_by_user_id(user.id) }
    set { can :read and can :read_roster and can :manage and can :manage_content and can :manage_students and can :manage_admin_users and
      can :manage_files and can :moderate_forum and
      can :post_to_forum and
      can :send_messages and can :create_conferences and
      can :create_collaborations and can :read_roster and
      can :manage_calendar and
      can :update and can :delete and can :create }
    
    given { |user| user && self.invited_users.include?(user) }
    set { can :read }
    
    given { |user, session| self.context && self.context.grants_right?(user, session, :participate_as_student) && self.context.allow_student_organized_groups }
    set { can :create }
    
    given { |user, session| self.context && self.context.grants_right?(user, session, :manage_groups) }
    set { can :read and can :read_roster and can :manage and can :manage_content and can :manage_students and can :manage_admin_users and can :update and can :delete and can :create and can :moderate_forum and can :post_to_forum }
    
    given { |user, session| self.context && self.context.grants_right?(user, session, :view_group_pages) }
    set { can :read and can :read_roster }
  end

  def file_structure_for(user)
    User.file_structure_for(self, user)
  end
  
  def is_a_context?
    true
  end

  def members_json_cached
    Rails.cache.fetch(['group_members_json', self].cache_key) do
      self.users.map {|u| { :user_id => u.id, :name => u.last_name_first } }
    end
  end

  def members_count_cached
    Rails.cache.fetch(['group_members_count', self].cache_key) do
      self.members_json_cached.length
    end
  end

  TAB_HOME = 0
  TAB_PAGES = 1
  TAB_PEOPLE = 2
  TAB_DISCUSSIONS = 3
  TAB_CHAT = 4
  TAB_FILES = 5
  def tabs_available(user=nil, opts={})
    available_tabs = [
      { :id => TAB_HOME,        :label => "Home", :href => :group_path }, 
      { :id => TAB_PAGES,       :label => "Pages", :href => :group_wiki_pages_path }, 
      { :id => TAB_PEOPLE,      :label => "People", :href => :group_users_path }, 
      { :id => TAB_DISCUSSIONS, :label => "Discussions", :href => :group_discussion_topics_path }, 
      { :id => TAB_CHAT,        :label => "Chat", :href => :group_chat_path }, 
      { :id => TAB_FILES,       :label => "Files", :href => :group_files_path }
    ]
  end

  def self.serialization_excludes; [:uuid]; end
  
  def self.process_migration(data, migration)
    groups = data['groups'] ? data['groups']: []
    to_import = migration.to_import 'groups'
    groups.each do |group|
      if group['migration_id'] && (!to_import || to_import[group['migration_id']])
        import_from_migration(group, migration.context)
      end
    end
  end
  
  def self.import_from_migration(hash, context, item=nil)
    hash = hash.with_indifferent_access
    return nil if hash[:migration_id] && hash[:groups_to_import] && !hash[:groups_to_import][hash[:migration_id]]
    item ||= find_by_context_id_and_context_type_and_id(context.id, context.class.to_s, hash[:id])
    item ||= find_by_context_id_and_context_type_and_migration_id(context.id, context.class.to_s, hash[:migration_id]) if hash[:migration_id]
    item ||= context.groups.new
    context.imported_migration_items << item if context.imported_migration_items && item.new_record?
    item.migration_id = hash[:migration_id]
    item.name = hash[:title]
    item.category = hash[:group_category] || 'Imported Groups'
    
    item.save!
    context.imported_migration_items << item
    item
  end
end
