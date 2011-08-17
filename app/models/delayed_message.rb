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

class DelayedMessage < ActiveRecord::Base
  belongs_to :notification
  belongs_to :notification_policy
  belongs_to :context, :polymorphic => true
  belongs_to :communication_channel
  
  
  validates_length_of :summary, :maximum => maximum_text_length, :allow_nil => true, :allow_blank => true
  validates_presence_of :communication_channel_id

  before_save :set_send_at
  
  def summary=(val)
    if !val || val.length < self.class.maximum_text_length
      write_attribute(:summary, val)
    else
      write_attribute(:summary, val[0,self.class.maximum_text_length])
    end
  end
  
  named_scope :for, lambda { |context|
    case context
    when :daily
      { :conditions => { :frequency => 'daily' } }
    when :weekly
      { :conditions => { :frequency => 'weekly' } }
    when Notification
      { :conditions => { :notification_id => context.id} }
    when NotificationPolicy
      { :conditions => { :notification_policy_id => context.id} }
    when CommunicationChannel
      { :conditions => { :communication_channel_id => context.id} }
    else
      { :conditions => { :context_id => context.id, :context_type => context.class.base_ar_class.to_s } }
    end
  }
  
  named_scope :by, lambda {|field| { :order => field } }
  
  named_scope :in_state, lambda { |state|
    { :conditions => ["workflow_state = ?", state.to_s]}
  }
  
  named_scope :to_summarize, lambda {
    { :conditions => ['delayed_messages.workflow_state = ? and delayed_messages.send_at <= ?', 'pending', Time.now.utc ] }
  }
  
  named_scope :next_to_summarize, lambda {
    { :conditions => ['delayed_messages.workflow_state = ?', 'pending'], :order => :send_at, :limit => 1 }
  }
  
  def self.ids_for_messages_with_communication_channel_id(cc_id)
    dm_ids = DelayedMessage.connection.select_values(
      "SELECT id
         FROM delayed_messages
        WHERE workflow_state = 'pending' AND send_at <= '#{Time.now.to_s(:db)}' AND communication_channel_id = #{cc_id}")
  end
  
  include Workflow
  
  workflow do
    state :pending do
      event :begin_send, :transitions_to => :sent do
        self.batched_at = Time.now
      end
      event :cancel, :transitions_to => :cancelled
    end
    
    state :cancelled
    state :sent
  end
  
  def linked_name=(name)
  end
  
  # This sets up a message and parses it internally.  Any template can
  # have these variables to build a message.  The most important one will
  # probably be delayed_messages, from which the right links and summaries
  # should be deliverable. After this is run on a list of delayed messages,
  # the regular dispatch process will take place. 
  def self.summarize(delayed_message_ids)
    delayed_messages = DelayedMessage.scoped(:include => :notification, :conditions => {:id => delayed_message_ids.uniq}).compact
    uniqs = {}
    # only include the most recent instance of each notification-context pairing
    delayed_messages.each do |m|
      uniqs[[m.context_id, m.context_type, m.notification_id]] = m
    end
    delayed_messages = uniqs.map{|key, val| val}.compact
    delayed_messages = delayed_messages.sort_by{|dm| [dm.notification.sort_order, dm.notification.category] }
    first = delayed_messages.detect{|m| m.communication_channel}
    to = first.communication_channel rescue nil
    return nil unless to
    return nil if delayed_messages.empty?
    user = to.user rescue nil
    context = delayed_messages.select{|m| m.context}.first.context
    notification = Notification.find_by_name('Summaries')
    path = HostUrl.outgoing_email_address
    message = notification.messages.build(
      :subject => notification.subject,
      :to => to.path,
      :body => notification.body,
      :notification_name => notification.name,
      :notification => notification,
      :from => path,
      :communication_channel => to,
      :user => user
    )
    message.delayed_messages = delayed_messages
    message.context = context
    message.asset_context = context.context(user) rescue context
    message.delay_for = 0
    message.parse!
    message.save
  end
  
  protected
    def set_send_at
      # Find the user's timezone
      if self.communication_channel and self.communication_channel.user
        user = self.communication_channel.user
        time_zone = ActiveSupport::TimeZone.us_zones.find {|zone| zone.name == user.time_zone}
      else
        time_zone = ActiveSupport::TimeZone.us_zones.find {|zone| zone.name == 'Mountain Time (US & Canada)'}
      end

      time_zone ||= ActiveSupport::TimeZone.us_zones.find {|zone| zone.name == 'Mountain Time (US & Canada)'}
      time_zone ||= Time.zone

      # I got tired of trying to figure out time zones in my head, and I realized
      # if we do it this way, Rails will take care of it all for us!
      target = ActiveSupport::TimeWithZone.new(Time.now.utc, time_zone)
      if self.frequency == 'weekly'
        target = target.next_week.advance(:day => -2).change(:hour => 20)
      elsif target.hour >= 18
        target = target.tomorrow.change(:hour => 18)
      else
        target = target.change(:hour => 18)
      end

      # Set the send_at value
      self.send_at ||= target
    end

end
