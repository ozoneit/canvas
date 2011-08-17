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

require 'open_object'
require 'set'

class StreamItem < ActiveRecord::Base
  serialize :data

  has_many :stream_item_instances, :dependent => :delete_all
  has_many :users, :through => :stream_item_instances
  
  def stream_data(viewing_user_id)
    res = data.is_a?(OpenObject) ? data : OpenObject.new
    res.assert_hash_data
    res.user_id ||= viewing_user_id
    if res.type == 'ContextMessage'
      res.sub_messages = (res.all_sub_messages || []).select{|m| m.user_id == viewing_user_id || m.recipients.include?(viewing_user_id) }
    end
    res
  end
  
  def prepare_context_message(message)
    res = message.attributes
    users = message.recipient_users.map{|u| u.attributes.slice('id', 'name', 'short_name')}
    res['recipients_count'] = users.length
    res['recipient_users'] = users if users.length <= 15
    res['formatted_body'] = message.formatted_body(250)
    res.delete 'body'
    res[:attachments] = message.attachments.map do |file|
      hash = file.attributes
      hash['readable_size'] = file.readable_size
      hash['scribdable?'] = file.scribdable?
      hash
    end
    code = message.context_code rescue nil
    if code
      res['context_short_name'] = Rails.cache.fetch(['short_name_lookup', code].cache_key) do
        Context.find_by_asset_string(code).short_name rescue ""
      end
    end
    res['user_short_name'] = message.user.short_name if message.user
    res
  end
  
  def asset
    @obj ||= ActiveRecord::Base.find_by_asset_string(self.item_asset_string, StreamItem.valid_asset_types)
  end
  
  def regenerate!(obj=nil)
    obj ||= asset
    return nil if self.item_asset_string == 'message_'
    if !obj || (obj.respond_to?(:workflow_state) && obj.workflow_state == 'deleted')
      self.destroy
      return nil
    end
    res = generate_data(obj)
    self.save
    res
  end
  
  def self.delete_all_for(asset, original_asset_string=nil)
    root_asset = nil
    root_asset = root_object(asset)
    
    root_asset_string = root_asset && root_asset.asset_string
    root_asset_string ||= asset.asset_string if asset.respond_to?(:asset_string)
    root_asset_string ||= asset if asset.is_a?(String)
    original_asset_string ||= root_asset_string
    
    return if root_asset_string == 'message_'
    # if this is a sub-message, regenerate instead of deleting
    if root_asset && root_asset.asset_string != original_asset_string
      items = StreamItem.for_item_asset_string(root_asset_string)
      items.each{|i| i.regenerate!(root_asset) }
      return
    end
    
    # Can't use delete_all here, since we need the destroy to fire and delete
    # the StreamItemInstances as well.
    StreamItem.find(:all, :conditions => {:item_asset_string => root_asset_string}).each(&:destroy) if root_asset_string
  end
  
  def self.valid_asset_types
    [
      :assignment,:submission,:submission_comment,:context_message,
      :discussion_topic, :discussion_entry, :message,
      :collaboration, :web_conference
    ]
  end
  
  def self.root_object(object)
    if object.is_a?(String)
      object = ActiveRecord::Base.find_by_asset_string(object, valid_asset_types) rescue nil
      object ||= ActiveRecord::Base.initialize_by_asset_string(object, valid_asset_types) rescue nil
    end
    case object
    when DiscussionEntry
      object.discussion_topic
    when Submission
      object
    when ContextMessage
      object.root_context_message || object
    when SubmissionComment
      object.submission
    else
      object
    end
  end

  def generate_data(object)
    res = {}

    self.context_code ||= object.context_code rescue nil
    self.context_code ||= object.context.asset_string rescue nil

    case object
    when DiscussionTopic
      object = object
      res = object.attributes
      res['total_root_discussion_entries'] = object.root_discussion_entries.active.count
      res[:root_discussion_entries] = object.root_discussion_entries.active.reverse[0,10].reverse.map do |entry|
        hash = entry.attributes
        hash['user_short_name'] = entry.user.short_name if entry.user
        hash['truncated_message'] = entry.truncated_message(250)
        hash.delete 'message'
        hash
      end
      if object.attachment
        hash = object.attachment.attributes.slice('id', 'display_name')
        hash['scribdable?'] = object.attachment.scribdable?
        res[:attachment] = hash
      end
    when ContextMessage
      if object.root_context_message
        object = object.root_context_message
        res = prepare_context_message(object)
        res[:all_sub_messages] = object.sub_messages.map do |message|
          prepare_context_message(message)
        end
      else
        res = prepare_context_message(object)
      end
    when Message
      res = object.attributes
      res['notification_category'] = object.notification_category
      if object.asset_context_type
        self.context_code = "#{object.asset_context_type.underscore}_#{object.asset_context_id}"
      end
    when Assignment
      return nil
      res = object.attributes
      res['submission_count'] = object.submissions.having_submission.count
      res['submissions'] = object.submissions.having_submission[0..5].map do |submission|
        hash = submission.attributes
        hash['user_short_name'] = submission.user.name if submission.user
        hash
      end
    when Submission
      res = object.attributes
      res['assignment'] = object.assignment.attributes.slice('id', 'title', 'due_at', 'points_possible', 'submission_types')
      res[:submission_comments] = object.submission_comments.select{|c| true }.map do |comment|
        hash = comment.attributes
        hash['formatted_body'] = comment.formatted_body(250)
        hash.delete 'body'
        hash['context_code'] = comment.context_code
        hash['user_short_name'] = comment.author.short_name if comment.author
        hash
      end
    when Collaboration
      res = object.attributes
      res['users'] = object.users.map{|u| u.attributes.slice('id', 'name', 'short_name')}
    when WebConference
      res = object.attributes
      res['users'] = object.users.map{|u| u.attributes.slice('id', 'name', 'short_name')}
    else
      raise "Unexpected stream item type: #{object.class.to_s}"
    end
    code = self.context_code
    if code
      res['context_short_name'] = Rails.cache.fetch(['short_name_lookup', code].cache_key) do
        Context.find_by_asset_string(code).short_name rescue ""
      end
    end
    res['type'] = object.class.to_s
    res['user_short_name'] = object.user.short_name rescue nil
    res['context_code'] = self.context_code
    res = OpenObject.process(res)

    self.item_asset_string = object.asset_string
    self.data = res
  end

  def self.generate_or_update(object)
    item = nil
    # we can't coalesce messages that weren't ever saved to the DB
    unless object.asset_string == 'message_'
      item = StreamItem.find_by_item_asset_string(object.asset_string)
    end
    if item
      item.regenerate!(object)
    else
      item = self.new
      item.generate_data(object)
      item.save
    end
    item
  end

  def self.generate_all(object, user_ids)
    user_ids ||= []
    user_ids.uniq!
    return [] if user_ids.empty?

    # Make the StreamItem
    object = get_parent_for_stream(object)
    res = StreamItem.generate_or_update(object)

    # Then insert a StreamItemInstance for each user in user_ids
    instance_ids = []
    StreamItemInstance.transaction do
      user_ids.each do |user_id|
        i = res.stream_item_instances.create(:user_id => user_id)
        instance_ids << i.id
      end
    end
    smallest_generated_id = instance_ids.min || 0

    # Then delete any old instances from these users' streams.
    # This won't actually delete StreamItems out of the table, it just deletes
    # the join table entries.
    # Old stream items are deleted in a periodic job.
    conn = ActiveRecord::Base.connection
    StreamItemInstance.delete_all(
          ["user_id in (?) AND stream_item_id = ? AND id < ?",
          user_ids, res.id, smallest_generated_id])

    # Here is where we used to go through and update the stream item for anybody
    # not in user_ids who had the item in their stream, so that the item would
    # be up-to-date, but not jump to the top of their stream. Now that
    # we're updating StreamItems in-place and just linking to them through
    # StreamItemInstances, this happens automatically.
    # If a teacher leaves a comment for a student, for example
    # we don't want that to jump to the top of the *teacher's* stream, but
    # if it's still visible on the teacher's stream then it had better show
    # the teacher's comment even if it is farther down.

    # touch all the users to invalidate the cache
    User.update_all({:updated_at => Time.now}, {:id => user_ids})

    return [res]
  end

  def self.get_parent_for_stream(object)
    object = object.discussion_topic if object.is_a?(DiscussionEntry)
    object = object.submission if object.is_a?(SubmissionComment)
    object = object.root_context_message || object if object.is_a?(ContextMessage)
    object
  end

  # delete old stream items and the corresponding instances before a given date
  # returns the number of destroyed stream items
  def self.destroy_stream_items(before_date, touch_users = true)
    user_ids = Set.new
    count = 0

    query = { :conditions => ['updated_at < ?', before_date] }
    if touch_users
      query[:include] = 'stream_item_instances'
    end

    self.find_each(query) do |item|
      count += 1
      if touch_users
        user_ids.add(item.stream_item_instances.map { |i| i.user_id })
      end
      # this will destroy the associated stream_item_instances as well
      item.destroy
    end

    unless user_ids.empty?
      # touch all the users to invalidate the cache
      User.update_all({:updated_at => Time.now}, {:id => user_ids.to_a})
    end

    count
  end

  named_scope :for_user, lambda {|user|
    {:conditions => ['stream_item_instances.user_id = ?', user.id],
      :include => :stream_item_instances }
  }
  named_scope :for_context_codes, lambda {|codes|
    {:conditions => {:context_code => codes} }
  }
  named_scope :for_item_asset_string, lambda{|string|
    {:conditions => {:item_asset_string => string} }
  }
  named_scope :before, lambda {|id|
    {:conditions => ['id < ?', id], :order => 'updated_at DESC', :limit => 21 }
  }
  named_scope :after, lambda {|start_at| 
    {:conditions => ['updated_at > ?', start_at], :order => 'updated_at DESC', :limit => 21 }
  }
end
