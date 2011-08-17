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

module SendToInbox

  module SendToInboxClassMethods
    def self.extended(klass)
      klass.send(:class_inheritable_accessor, :send_to_inbox_block)
    end
 
    def on_create_send_to_inboxes(&block)
      self.send_to_inbox_block = block
      after_create :queue_create_inbox_items
    end
  end
 
  module SendToInboxInstanceMethods
    def queue_create_inbox_items
      if ENV['RAILS_ENV'] == 'production'
        send_later(:create_inbox_items)
      else
        create_inbox_items
      end
    end
    
    def create_inbox_items
      self.extend TextHelper
      block = self.class.send_to_inbox_block
      inbox_results = self.instance_eval(&block) || {}
      inbox_results[:body_teaser] = if inbox_results[:body]
                                      truncate_text(inbox_results[:body], :max_length => 255)
                                    elsif inbox_results[:html_body]
                                      strip_and_truncate(inbox_results[:html_body] || "", :max_length => 255)
                                    else
                                      ""
                                    end
      @inbox_item_recipient_ids = (Array(inbox_results[:recipients]) || []).each{|r| User.infer_id(i) rescue nil}.compact
      sender_id = User.infer_id(inbox_results[:sender]) rescue nil
      @inbox_item_recipient_ids.each do |user_id|
        if user_id
          InboxItem.create(
            :user_id => user_id,
            :asset => self,
            :subject => inbox_results[:subject] || "No Subject",
            :body_teaser => inbox_results[:body_teaser],
            :sender_id => sender_id
          )
        end
      end
    rescue => e
      ErrorLogging.log_error(:default, {
        :message => "SendToInbox failure",
        :caught_message => e.to_s,
        :backtrace => e.backtrace.join("<br/>\n")
      }) if ENV['RAILS_ENV'] == 'production'
      nil
    end
    
    def inbox_item_recipient_ids
      @inbox_item_recipient_ids
    end
 
  end
 
  def self.included(klass)
    klass.send :include, SendToInboxInstanceMethods
    klass.extend SendToInboxClassMethods
  end
end
 
