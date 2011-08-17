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

class DelayedNotification < ActiveRecord::Base
  include Workflow
  belongs_to :asset, :polymorphic => true
  belongs_to :notification
  
  serialize :recipient_keys
  
  workflow do
    state :to_be_processed do
      event :do_process, :transitions_to => :processed
    end
    state :processed
    state :errored
  end
  
  def self.process(asset, notification, recipient_keys)
    dn = DelayedNotification.new(:asset => asset, :notification => notification, :recipient_keys => recipient_keys)
    dn.process
  end
  
  def process
    tos = self.to_list
    res = self.notification.create_message(self.asset, tos) if self.asset && !tos.empty?
    self.do_process unless self.new_record?
    res
  rescue => e
    ErrorLogging.log_error(:default, {
      :message => "Delayed Notification processing failed",
      :object => self.inspect.to_s,
      :error_type => (e.inspect rescue ''),
      :exception_message => (e.message rescue ''),
      :failure_status => (e.to_s rescue ''),
      :backtrace => (e.backtrace rescue '')
    })
    logger.error "delayed notification processing failed: #{e.message}\n#{e.backtrace.join "\n"}"
    self.workflow_state = 'errored'
    self.save
    []
  end
  
  def to_list
    lookups = {}
    (recipient_keys || []).each do |key|
      pieces = key.split('_')
      id = pieces.pop
      klass = pieces.join('_').classify.constantize
      lookups[klass] ||= []
      lookups[klass] << id
    end
    res = []
    lookups.each do |klass, ids|
      includes = []
      includes = [:user] if klass == CommunicationChannel
      res += klass.find(:all, :conditions => {:id => ids}, :include => includes) rescue []
    end
    res.uniq
  end
  memoize :to_list
  
  named_scope :to_be_processed, lambda {|limit|
    {:conditions => ['delayed_notifications.workflow_state = ?', 'to_be_processed'], :limit => limit, :order => 'delayed_notifications.created_at'}
  }
end
