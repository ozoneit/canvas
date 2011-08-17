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

class GradingStandard < ActiveRecord::Base
  attr_accessible :title, :standard_data
  belongs_to :context, :polymorphic => true
  belongs_to :user
  has_many :assignments
  serialize :data
  
  before_save :update_usage_count
  
  adheres_to_policy
  
  def update_usage_count
    self.usage_count = self.assignments.active.length
    self.context_code = "#{self.context_type.underscore}_#{self.context_id}" rescue nil
  end
  
  set_policy do
    given {|user| true }
    set { can :read and can :create }
    
    given {|user| self.assignments.active.length < 2}
    set { can :update and can :delete }
  end
  
  def update_data(params)
    self.data = params.to_a.sort_by{|i| i[1]}.reverse
  end
  
  def display_name
    res = ""
    res += self.user.name + ", " rescue ""
    res += self.context.name rescue ""
    res = "Unknown Details" if res.empty?
    res
  end
  
  def grading_scheme
    res = {}
    begin
      self.data.sort_by{|i| i[1]}.reverse.each do |i|
        res[i[0].to_s] = i[1].to_f
      end
    rescue
      res = GradingStandard.default_grading_scheme
    end
    res
  end
  
  def standard_data=(params={})
    params ||= {}
    res = {}
    params.each do |key, row|
      res[row[:name]] = (row[:value].to_f / 100.0) if row[:name] && row[:value]
    end
    self.data = res.to_a.sort_by{|i| i[1]}.reverse
  end
  
  def self.default_grading_standard
    default_grading_scheme.to_a.sort_by{|i| i[1]}.reverse
  end
  
  def self.default_grading_scheme
    {
      "A" => 1.0,
      "A-" => 0.93,
      "B+" => 0.89,
      "B" => 0.86,
      "B-" => 0.83,
      "C+" => 0.79,
      "C" => 0.76,
      "C-" => 0.73,
      "D+" => 0.69,
      "D" => 0.66,
      "D-" => 0.63,
      "F" => 0.6
    }
    # grades = {
      # "A" => 1.0,
      # "A-" => 0.925,
      # "B+" => 0.825,
      # "B" => 0.75,
      # "B-" => 0.675,
      # "C+" => 0.575,
      # "C" => 0.50,
      # "C-" => 0.425,
      # "D+" => 0.325,
      # "D" => 0.25,
      # "D-" => 0.175,
      # "F" => 0.0
    # }
  end
end
