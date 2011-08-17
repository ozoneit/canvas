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

class CommunicationChannel < ActiveRecord::Base
  # You should start thinking about communication channels
  # as independent of pseudonyms
  include Workflow

  attr_accessible :user, :path, :path_type, :build_pseudonym_on_confirm, :pseudonym

  belongs_to :pseudonym
  has_many :pseudonyms
  belongs_to :user
  has_many :notification_policies, :dependent => :destroy
  has_many :messages
  
  before_save :consider_retiring, :assert_path_type, :set_confirmation_code
  before_save :consider_building_pseudonym
  before_validation :validate_unique_path
  after_create :setup_default_notification_policies
  after_save :remove_other_paths
  
  acts_as_list :scope => :user_id
  
  has_a_broadcast_policy
  
  attr_reader :request_password
  attr_reader :send_confirmation

  def setup_default_notification_policies
    (NotificationPolicy.send_later(:defaults_for, self.user) if self.user && self.user.communication_channels.length == 1 && self.user.notification_policies.empty?) rescue nil
  end
  protected :setup_default_notification_policies
  
  def remove_other_paths
    if @state_was != 'active' && self.active? && self.path_type == 'email'
      CommunicationChannel.delete_all(['path = ? AND path_type = ? AND id != ?', self.path, self.path_type, self.id])
    end
  end
  
  def pseudonym
    self.user.pseudonyms.find_by_unique_id(self.path)
  end

  def validate_unique_path
    @state_was = self.workflow_state_was
    if (self.new_record? || (self.workflow_state_was != 'active' && self.workflow_state == 'active')) && self.path_type == 'email' && self.path
      ccs = CommunicationChannel.find_all_by_path_and_path_type_and_workflow_state(self.path, self.path_type, 'active')
      if ccs.any?{|cc| cc != self }
        self.errors.add(:path, "The #{self.path_type} address #{self.path} has already been activated for another account")
        return false
      end
    end
  end
  
  set_broadcast_policy do |p|
    p.dispatch :forgot_password
    p.to { self }
    p.whenever { |record|
      @request_password
    }
    
    p.dispatch :confirm_registration
    p.to { self }
    p.whenever { |record|
      @send_confirmation and
      (record.workflow_state == 'active' || 
        (record.workflow_state == 'unconfirmed' and (self.user.pre_registered? || self.user.creation_pending?))) and
      self.path_type == 'email'
    }

    p.dispatch :confirm_email_communication_channel
    p.to { self }
    p.whenever { |record| 
      @send_confirmation and
      record.workflow_state == 'unconfirmed' and self.user.registered? and
      self.path_type == 'email'
    }
    
    p.dispatch :merge_email_communication_channel
    p.to { self }
    p.whenever {|record|
      @send_merge_notification and
      self.path_type == 'email'
    }
    
    p.dispatch :confirm_sms_communication_channel
    p.to { self }
    p.whenever { |record|
      @send_confirmation and
      record.workflow_state == 'unconfirmed' and
      self.path_type == 'sms' and
      !self.user.creation_pending?
    }
  end
  
  def active_pseudonyms
    self.user.pseudonyms.active
  end
  memoize :active_pseudonyms
  
  def path_description
    if self.path_type == 'facebook'
      res = self.user.user_services.for_service('facebook').first.service_user_name + " (facebook)" rescue nil
      res ||= 'Facebook Account'
      res
    else
      self.path
    end
  end
  
  def forgot_password!
    @request_password = true
    set_confirmation_code(true)
    self.save!
    @request_password = false
  end
  
  def send_confirmation!
    @send_confirmation = true
    self.save!
    @send_confirmation = false
  end
  
  def send_merge_notification!
    @send_merge_notification = true
    self.save!
    @send_merge_notification = false
  end
  
  # If you are creating a new communication_channel, do nothing, this just
  # works.  If you are resetting the confirmation_code, call @cc.
  # set_confirmation_code(true), or just save the record to leave the old
  # confirmation code in place. 
  def set_confirmation_code(reset=false)
    self.confirmation_code = nil if reset
    if self.path_type == 'email' or self.path_type.nil?
      self.confirmation_code ||= AutoHandle.generate(nil, 25)
    else
      self.confirmation_code ||= AutoHandle.generate
    end
  end
  
  named_scope :for, lambda { |context| 
    case context
    when User
      { :conditions => ['communication_channels.user_id = ?', context.id] }
    when Notification
      { :include => [:notification_policies], :conditions => ['notification_policies.notification_id = ?', context.id] }
    else
      {}
    end
  }
  
  named_scope :email, lambda{
    {:conditions => ['path_type = ?', 'email']}
  }
  
  named_scope :active_email_paths, lambda {|paths|
    {
      :conditions => {:path_type => 'email', :path => paths, :workflow_state => 'active'},
      :include => :user
    }
  }
  
  named_scope :unretired, lambda {
    {:conditions => ['communication_channels.workflow_state != ?', 'retired'] }
  }
  
  named_scope :for_notification_frequency, lambda {|notification, frequency|
    { :include => [:notification_policies], :conditions => ['notification_policies.notification_id = ? and notification_policies.frequency = ?', notification.id, frequency] }
  }
  
  named_scope :include_policies, lambda {
    {:include => :notification_policies }
  }
  
  named_scope :in_state, lambda { |state| { :conditions => ["communication_channels.workflow_state = ?", state.to_s]}}
  named_scope :of_type, lambda {|type| { :conditions => ['communication_channels.path_type = ?', type] } }
  
  def can_notify?
    self.notification_policies.any? { |np| np.frequency == 'never' } ? false : true
  end
  
  # This is the re-worked find_for_all.  It is created to get all
  # communication channels that have a specific, valid notification policy
  # setup for it, or the default communication channel for a user.  This,
  # of course, doesn't hold for registration, since no policy is expected
  # to intervene.  All registration notices go to the passed-in
  # communication channel.  That information is being handed to us from
  # the context of the notification policy being fired. 
  def self.find_all_for(user=nil, notification=nil, cc=nil, frequency='immediately')
    return [] unless user && notification
    return [cc] if cc and notification.registration?
    return [] unless user.registered?
    policy_matches_frequency = {}
    policy_for_channel = {}
    can_notify = {}
    user.notification_policies.select{|p| p.notification_id == notification.id}.each do |policy|
      policy_matches_frequency[policy.communication_channel_id] = true if policy.frequency == frequency
      policy_for_channel[policy.communication_channel_id] = true
      can_notify[policy.communication_channel_id] = false if policy.frequency == 'never'
    end
    all_channels = user.communication_channels.unretired
    communication_channels = all_channels.select{|cc| policy_matches_frequency[cc.id] }
    all_channels = all_channels.select{|cc| cc.active? && policy_for_channel[cc.id] }
    
    # The trick here is that if the user has ANY policies defined for this notification
    # then we shouldn't overwrite it with the default channel -- but we only want to
    # return the list of channels for immediate dispatch
    communication_channels = [user.communication_channels.first] if all_channels.empty? && notification.default_frequency == 'immediately'
    communication_channels.compact!
    
    # Remove ALL channels if one is 'never'?  No, I think we should just remove any paths that are set to 'never'
    # User can say NEVER email me, but SMS me right away.
    communication_channels.reject!{|cc| can_notify[cc] == false}
    communication_channels
  end
  
  def self.ids_with_pending_delayed_messages
    CommunicationChannel.connection.select_values(
      "SELECT distinct communication_channel_id
         FROM delayed_messages
        WHERE workflow_state = 'pending' AND send_at <= '#{Time.now.to_s(:db)}'")
  end
  
  
  # A formatted path_type
  def proper_type
    assert_path_type
    case path_type
    when "email"
      "Email Address"
    when "sms"
      "Cell Number"
    else
      path_type.capitalize
    end
  end
  
  def move_to_user(user, migrate=true)
    return unless user
    if self.pseudonym && self.pseudonym.unique_id == self.path
      self.pseudonym.move_to_user(user, migrate)
    else
      old_user_id = self.user_id
      self.user_id = user.id
      self.save!
      if old_user_id
        Pseudonym.update_all({:user_id => user.id}, {:user_id => old_user_id, :unique_id => self.path})
        User.update_all({:updated_at => Time.now}, {:id => [old_user_id, user.id]})
      end
    end
  end
  
  
  
  def consider_building_pseudonym
    if self.build_pseudonym_on_confirm && self.active?
      self.build_pseudonym_on_confirm = false
      pseudonym = self.user.pseudonyms.build(:unique_id => self.path, :account => Account.default)
      existing_pseudonym = self.user.pseudonyms.active.select{|p| p.account_id == Account.default.id }.first
      if existing_pseudonym
        pseudonym.password_salt = existing_pseudonym.password_salt
        pseudonym.crypted_password = existing_pseudonym.crypted_password
      end
      pseudonym.save!
    end
    true
  end
  
  def consider_retiring
    self.retire if self.bounce_count >= 5
  end
  
  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'retired'
    self.save
  end
  
  workflow do
    
    state :unconfirmed do
      event :confirm, :transitions_to => :active do
        self.set_confirmation_code(true)
      end
      event :retire, :transitions_to => :retired
    end
    
    state :active do
      event :retire, :transitions_to => :retired
    end
    
    state :retired do
      event :re_activate, :transitions_to => :active do
        self.bounce_count = 0
      end
    end
    state :deleted
  end
  
  def assert_user(params={}, &block)
    self.user ||= User.create!({:name => self.path}.merge(params), &block)
    self.save
    self.user
  end

  # This is setup as a default in the database, but this overcomes misspellings.
  def assert_path_type
    pt = self.path_type
    self.path_type = 'email' unless pt == 'email' or pt == 'sms' or pt == 'chat' or pt == 'facebook'
  end
  protected :assert_path_type
    
  def self.serialization_excludes; [:confirmation_code]; end
end
