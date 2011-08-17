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

class UserNote < ActiveRecord::Base
  include Workflow
  attr_accessible :user, :note, :title, :creator
  adheres_to_policy
  belongs_to :user
  belongs_to :creator, :class_name => 'User', :foreign_key => :created_by_id
  validates_length_of :note, :maximum => maximum_text_length, :allow_nil => true, :allow_blank => true
  after_save :update_last_user_note

  sanitize_field :note, Instructure::SanitizeField::SANITIZE

  workflow do
    state :active
    state :deleted
  end
  
  named_scope :active, :conditions => ['workflow_state != ?', 'deleted']
  named_scope :desc_by_date, :order => 'created_at DESC'
  
  set_policy do
    given { |user| self.creator == user }
    set { can :delete and can :read }
    
    given { |user| self.user.grants_right?(user, nil, :delete_user_notes) }
    set { can :delete and can :read }
    
    given { |user| self.user.grants_right?(user, nil, :read_user_notes) }
    set { can :read }
  end
  
  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    self.deleted_at = Time.now
    save!
  end
  
  def formatted_note(truncate=nil)
    self.extend TextHelper
    res = self.note
    res = truncate_html(self.note, :max_length => truncate, :words => true) if truncate
    res
  end
  
  def creator_name
    self.creator ? self.creator.name : nil
  end
  
  def update_last_user_note
    self.user.update_last_user_note
    self.user.save
  end
  
  def self.add_from_message(message)
    return unless message && message.recipients.size == 1
    to = message.recipient_users.first
    from = message.user
    if to.grants_right?(from, :create_user_notes)
      note = to.user_notes.new
      note.created_by_id = from.id
      note.title = "#{message.subject} (Added from a message)"
      note.note = message.body
      if root_note = message.root_context_message
        note.note += "\n\n-------------------------\n"
        note.note += "In reply to: #{root_note.subject}\nFrom: #{root_note.user.name}\n\n"
        note.note += root_note.body
      end
      # The note content built up above is all plaintext, but note is an html field.
      self.extend TextHelper
      note.note = format_message(note.note).first
      note.save
    end
  end
  
end
