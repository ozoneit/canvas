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

class GroupMembership < ActiveRecord::Base
  
  include Workflow
  
  belongs_to :group
  belongs_to :user
  
  before_save :ensure_mutually_exclusive_membership
  before_save :assign_uuid
  before_save :capture_old_group_id
  
  after_save :touch_groups
  
  before_destroy :touch_groups
  
  has_a_broadcast_policy
  
  named_scope :include_user, :include => :user
  
  named_scope :active, :conditions => ['group_memberships.workflow_state != ?', 'deleted']
  
  set_broadcast_policy do |p|
    p.dispatch :new_context_group_membership
    p.to { self.user }
    p.whenever {|record| record.just_created && record.accepted? && record.group && record.group.context }
    
    p.dispatch :new_context_group_membership_invitation
    p.to { self.user }
    p.whenever {|record| record.just_created && record.invited? && record.group && record.group.context }
    
    p.dispatch :group_membership_accepted
    p.to { self.user }
    p.whenever {|record| record.changed_state(:available, :requested) }
    
    p.dispatch :group_membership_rejected
    p.to { self.user }
    p.whenever {|record| record.changed_state(:rejected, :requested) }
  
    p.dispatch :new_student_organized_group
    p.to { self.group.context.admins }
    p.whenever {|record|
      record.group.context && 
      record.group.context.is_a?(Course) && 
      record.just_created &&
      record.group.group_memberships.count == 1 &&
      record.group.category == Group.student_organized_category
    }
  end
  
  def assign_uuid
    self.uuid ||= UUIDSingleton.instance.generate
    self.workflow_state = 'accepted' if self.requested? && self.group && self.group.auto_accept?(self.user)
  end
  protected :assign_uuid

  def ensure_mutually_exclusive_membership
    return unless self.group
    peer_groups = self.group.peer_groups.map(&:id)
    GroupMembership.find(:all, :conditions => { :group_id => peer_groups, :user_id => self.user_id }).each {|gm| gm.destroy }
  end
  protected :ensure_mutually_exclusive_membership
  
  attr_accessor :old_group_id
  def capture_old_group_id
    self.old_group_id = self.group_id_was if self.group_id_changed?
  end
  protected :capture_old_group_id
  
  def touch_groups
    groups_to_touch = [ self.group_id ]
    groups_to_touch << self.old_group_id if self.old_group_id
    Group.update_all({ :updated_at => Time.now }, { :id => groups_to_touch })
  end
  protected :touch_groups
  
  workflow do
    state :accepted
    state :invited do
      event :reject, :transitions_to => :rejected
      event :accept, :transitions_to => :accepted
    end
    state :requested
    state :rejected
    state :deleted
  end
  
  def self.serialization_excludes; [:uuid]; end
end
