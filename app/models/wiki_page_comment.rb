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

class WikiPageComment < ActiveRecord::Base
  include Workflow
  belongs_to :user
  belongs_to :wiki_page
  belongs_to :context, :polymorphic => true
  adheres_to_policy
  after_create :update_wiki_page_comments_count
  
  def update_wiki_page_comments_count
    WikiPage.update_all({:wiki_page_comments_count => self.wiki_page.wiki_page_comments.count}, {:id => self.wiki_page_id})
  end
  
  workflow do
    state :current
    state :old
    state :deleted
  end

  def formatted_body(truncate=nil)
    self.extend TextHelper
    res = format_message(comments).first
    res = truncate_html(res, :max_length => truncate, :words => true) if truncate
    res
  end
  
  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    self.save
  end
  
  set_policy do
    given{|user, session| self.cached_context_grants_right?(user, session, :manage_wiki) }
    set{ can :read and can :delete }
    
    given{|user, session| self.cached_context_grants_right?(user, session, :read) }
    set{ can :read }
    
    given{|user, session| user && self.user_id == user.id }
    set{ can :delete }
    
    given{|user, session| self.wiki_page.grants_right?(user, session, :read) }
    set{ can :read }
  end
  
  named_scope :active, lambda{
    {:conditions => ['workflow_state != ?', 'deleted'] }
  }
  named_scope :current, lambda{
    {:conditions => {:workflow_state => :current} }
  }
  named_scope :current_first, lambda{
    {:order => 'workflow_state'}
  }
end
