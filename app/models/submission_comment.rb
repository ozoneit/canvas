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

class SubmissionComment < ActiveRecord::Base
  include SendToInbox
  include SendToStream
  
  belongs_to :submission #, :touch => true
  belongs_to :author, :class_name => 'User'
  belongs_to :recipient, :class_name => 'User'
  belongs_to :assessment_request
  belongs_to :context, :polymorphic => true
  has_many :associated_attachments, :class_name => 'Attachment', :as => :context
  has_many :submission_comment_participants
  has_many :messages, :as => :context, :dependent => :destroy
  # too bad, this wont work.
  # has_many :comments_in_group, :class_name => "SubmissionComment", :foreign_key => "group_comment_id", :primary_key => "group_comment_id", :dependent => :destroy, :conditions => lambda{|sc| "id !=#{sc.id}"}

  validates_length_of :comment, :maximum => maximum_text_length, :allow_nil => true, :allow_blank => true
  validates_length_of :comment, :minimum => 1, :allow_nil => true, :allow_blank => true
  
  before_save :infer_details
  after_save :update_submission
  after_destroy :delete_other_comments_in_this_group
  after_create :update_participants

  serialize :cached_attachments
  
  def delete_other_comments_in_this_group
    return if !self.group_comment_id || @skip_destroy_callbacks
    SubmissionComment.find_all_by_group_comment_id(self.group_comment_id).select{|c| c != selc }.each do |comment|
      comment.skip_destroy_callbacks!
      comment.destroy
    end
  end
  
  def skip_destroy_callbacks!
    @skip_destroy_callbacks = true
  end
  
  has_a_broadcast_policy
  adheres_to_policy
  
  on_create_send_to_inboxes do
    if self.submission
      users = []
      if self.author_id == self.submission.user_id
        users = self.submission.context.admins_in_charge_of(self.author_id)
      else
        users = self.submission.user_id
      end
      submission = self.submission
      {
        :recipients => users,
        :subject => "#{submission.assignment.title}: #{submission.user.name}",
        :body => self.comment,
        :sender => self.author_id
      }
    end
  end
  
  def media_comment?
    self.media_comment_id && self.media_comment_type
  end
  
  on_create_send_to_streams do
    if self.submission
      if self.author_id == self.submission.user_id
        self.submission.context.admins_in_charge_of(self.author_id)
      else
        # self.submission.context.admins.map(&:id) + [self.submission.user_id] - [self.author_id]
        self.submission.user_id
      end
    end
  end

  set_policy do
    given {|user,session| !self.teacher_only_comment && self.submission.grants_right?(user, session, :read_grade) }
    set {can :read}
    
    given {|user| self.author == user}
    set {can :read and can :delete}
    
    given {|user, session| self.submission.grants_right?(user, session, :grade) }
    set {can :read and can :delete}
  end
  
  set_broadcast_policy do |p|
    p.dispatch :submission_comment
    p.to { [submission.user] - [author] }
    p.whenever {|record|
      record.just_created && 
      record.submission.assignment && (!record.submission.assignment.context.admins.include?(author) || record.submission.assignment.published?) && 
      (record.created_at - record.submission.created_at rescue 0) > 30
    }

    # Too noisy?
    p.dispatch :submission_comment_for_teacher
    p.to { submission.assignment.context.admins_in_charge_of(author_id) - [author] }
    p.whenever {|record|
      record.just_created && 
      record.submission.user_id == record.author_id && record.submission.submitted_at && 
      (record.created_at - record.submission.submitted_at rescue 0) > 30
    }
  end
  
  def update_participants
    self.submission_comment_participants.find_or_create_by_user_id_and_participation_type(self.submission.user_id, 'submitter')
    self.submission_comment_participants.find_or_create_by_user_id_and_participation_type(self.author_id, 'author')
    (submission.assignment.context.participating_admins - [author]).each do |user|
      self.submission_comment_participants.find_or_create_by_user_id_and_participation_type(user.id, 'admin')
    end
  end
  
  def reply_from(opts)
    user = opts[:user]
    message = opts[:text].strip
    user = nil unless user && self.context.users.include?(user)
    if !user
      raise "Only comment participants may reply to messages"
    elsif !message || message.empty?
      raise "Message body cannot be blank"
    else
      SubmissionComment.create!({
        :comment => message,
        :submission_id => self.submission_id,
        :recipient_id => self.recipient_id,
        :author_id => user.id,
        :context_id => self.context_id,
        :context_type => self.context_type
      })
    end
  end
  
  def context
    read_attribute(:context) || self.submission.assignment.context rescue nil
  end
  
  def attachment_ids=(ids)
    # raise "Cannot set attachment id's directly"
  end
  
  def attachments=(attachments)
    # Accept attachments that were already approved, those that were just created
    # or those that were part of some outside context.  This is all to prevent
    # one student from sneakily getting access to files in another user's comments,
    # since they're all being held on the assignment for now.
    attachments ||= []
    old_ids = (self.attachment_ids || "").split(",").map{|id| id.to_i}
    write_attribute(:attachment_ids, attachments.select{|a| old_ids.include?(a.id) || a.recently_created || a.context != self.submission.assignment }.map{|a| a.id}.join(","))
  end
  
  def infer_details
    self.author_name ||= self.author.short_name rescue "Someone"
    self.cached_attachments = self.attachments.map{|a| OpenObject.build('attachment', a.attributes) }
    self.context = self.read_attribute(:context) || self.submission.assignment.context rescue nil
  end
  
  def force_reload_cached_attachments
    self.cached_attachments = self.attachments.map{|a| OpenObject.build('attachment', a.attributes) }
    self.save
  end
  
  
  def attachments
    ids = (self.attachment_ids || "").split(",").map{|id| id.to_i}
    attachments = associated_attachments
    attachments += self.submission.assignment.attachments rescue []
    attachments.select{|a| ids.include?(a.id) }
  end
  
  def update_submission
    conn = ActiveRecord::Base.connection
    comments_count = SubmissionComment.find_all_by_submission_id(self.submission_id).length
    conn.execute("UPDATE submissions SET submission_comments_count=#{comments_count}, updated_at=#{conn.quote(Time.now.utc.to_s(:db))} WHERE id=#{self.submission_id}") rescue nil
  end
  
  def formatted_body(truncate=nil)
    self.extend TextHelper
    res = format_message(comment).first
    res = truncate_html(res, :max_length => truncate, :words => true) if truncate
    res
  end
  
  def context_code
    "#{self.context_type.downcase}_#{self.context_id}"
  end

  named_scope :after, lambda{|date|
    {:conditions => ['submission_comments.created_at > ?', date] }
  }
  named_scope :for_context, lambda{|context|
    {:conditions => ['submission_comments.context_id = ? AND submission_comments.context_type = ?', context.id, context.class.to_s] }
  }
  # protected :infer_details
  # named_scope :for, lambda {|user|
    # {:conditions => ['(submission_comments.recipient_id IS NULL OR submission_comments.recipient_id = ?)', (user ? user.id : 0)]}
  # }
end
