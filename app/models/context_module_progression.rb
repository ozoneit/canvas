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

class ContextModuleProgression < ActiveRecord::Base
  include Workflow
  attr_accessible :context_module, :user
  belongs_to :context_module
  belongs_to :user
  
  before_save :infer_defaults
  after_save :touch_user
  
  serialize :requirements_met
  
  def infer_defaults
    if self.completed?
      self.completed_at ||= Time.now
    else
      self.completed_at = nil
    end
  end
  
  def finished_item?(item)
    (self.requirements_met || []).any?{|r| r[:id] == item.id}
  end
  
  def collapsed?
    !!self.collapsed
  end
  
  def uncollapse!
    return if self.collapsed == false
    progressions = self.context_module.context.context_modules.include_tags_and_progressions.map(&:context_module_progressions).flatten
    progressions = progressions.select{|p| p.collapsed == false && self.user_id == p.user_id && p != self }
    ActiveRecord::Base.connection.execute("UPDATE context_module_progressions SET collapsed=NULL WHERE id IN (#{progressions.map(&:id).join(',')})") unless progressions.empty?
    self.collapsed = false
    self.save
  end
  
  def deep_evaluate(mod)
    mod = nil if mod && mod.id != self.context_module_id
    mod ||= self.context_module
    return if !mod.completion_requirements || mod.completion_requirements.empty?
    tags_hash = mod.content_tags_hash
    met = self.requirements_met || []
    orig_reqs = met.map{|r| "#{r[:id]}_#{r[:type]}"}.sort
    (mod.completion_requirements || []).each do |req|
      next if met.any?{|r| r[:id] == req[:id] && r[:type] == req[:type]}
      tag = tags_hash[req[:id]]
      if !req[:id] || !tag
        met << req
      elsif req[:type] == "must_view"
        view = false
        view = true if met.any?{|r| r[:id] == req[:id] }
        met << req if view
      elsif req[:type] == "must_contribute"
        
      elsif req[:type] == "must_submit"
        obj = tag.content
        if obj.is_a?(DiscussionTopic)
          obj = obj.assignment
        end
        if obj.is_a?(Assignment)
          met << req if self.user.submitted_submission_for(obj.id)
        elsif obj.is_a?(Quiz)
          met << req if self.user.attempted_quiz_submission_for(obj.id)
        end
      elsif req[:type] == "max_score"
        obj = tag.content
        sub = nil
        if obj.is_a?(Assignment)
          sub = self.user.submitted_submission_for(obj.id)
        elsif obj.is_a?(Quiz)
          sub = self.user.attempted_quiz_submission_for(obj.id)
        end
        met << req if sub && sub.score <= req[:max_score].to_f
      elsif req[:type] == "min_score"
        obj = tag.content
        sub = nil
        if obj.is_a?(Assignment)
          sub = self.user.submitted_submission_for(obj.id)
        elsif obj.is_a?(Quiz)
          sub = self.user.attempted_quiz_submission_for(obj.id)
        end
        met << req if sub && sub.score && sub.score >= req[:max_score].to_f
      end
    end
    new_reqs = met.map{|r| "#{r[:id]}_#{r[:type]}"}.sort
    self.requirements_met = met
    self.save if orig_reqs != new_reqs
  end
  
  named_scope :for_user, lambda{|user|
    {:conditions => {:user_id => user && user.id} }
  }
  named_scope :for_modules, lambda{|mods|
    mods = Array(mods)
    {:conditions => {:context_module_id => mods.map(&:id) } }
  }
  
  workflow do
    state :locked
    state :unlocked
    state :started
    state :completed
  end
end
