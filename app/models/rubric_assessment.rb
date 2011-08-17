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

# Associates an artifact with a rubric while offering an assessment and 
# scoring using the rubric.  Assessments are grouped together in one
# RubricAssociation, which may or may not have an association model.
class RubricAssessment < ActiveRecord::Base
  attr_accessible :rubric, :rubric_association, :user, :score, :data, :comments, :assessor, :artifact, :assessment_type
  belongs_to :rubric
  belongs_to :rubric_association
  belongs_to :user
  belongs_to :assessor, :class_name => 'User'
  belongs_to :artifact, :polymorphic => true, :touch => true
  has_many :assessment_requests, :dependent => :destroy
  adheres_to_policy
  serialize :data
  
  simply_versioned
  
  validates_presence_of :assessment_type
  validates_length_of :comments, :maximum => maximum_text_length, :allow_nil => true, :allow_blank => true
  
  before_save :update_artifact_parameters
  after_save :update_assessment_requests, :update_artifact
  after_save :track_outcomes
  
  def track_outcomes
    outcome_ids = (self.data || []).map{|r| r[:learning_outcome_id] }.compact.uniq
    send_later(:update_outcomes_for_assessment, outcome_ids) unless outcome_ids.empty?
  end
  
  def update_outcomes_for_assessment(outcome_ids=[])
    return if outcome_ids.empty?
    tags = self.rubric_association.association.learning_outcome_tags.find_all_by_learning_outcome_id(outcome_ids)
    (self.data || []).each do |rating|
      if rating[:learning_outcome_id]
        tags.select{|t| t.learning_outcome_id == rating[:learning_outcome_id]}.each do |tag|
          tag.create_outcome_result(self.user, self.rubric_association.association, self)
        end
      end
    end
  end
  
  def update_artifact_parameters
    if self.artifact_type == 'Submission' && self.artifact
      self.artifact_attempt = self.artifact.attempt
    end
  end
  
  def update_assessment_requests
    requests = self.assessment_requests
    requests += self.rubric_association.assessment_requests.find_all_by_assessor_id_and_asset_id_and_asset_type(self.assessor_id, self.artifact_id, self.artifact_type)
    requests.each { |a|
      a.attributes = {:rubric_assessment => self, :assessor => self.assessor}
      a.complete
    }
  end
  protected :update_assessment_requests
  
  def attempt
    self.artifact_type == 'Submission' ? self.artifact.attempt : nil
  end
  
  def update_artifact
    if self.artifact_type == 'Submission' && self.artifact
      Submission.update_all({:has_rubric_assessment => true}, {:id => self.artifact.id})
      if self.rubric_association && self.rubric_association.use_for_grading && self.artifact.score != self.score
        if self.rubric_association.association.grants_right?(self.assessor, nil, :grade)
          # TODO: this should go through assignment.grade_student to 
          # handle group assignments.
          self.artifact.workflow_state = 'graded'
          self.artifact.update_attributes(:score => self.score, :graded_at => Time.now, :grade_matches_current_submission => true, :grader => self.assessor)
        end
      end
    end
  end
  protected :update_artifact
  
  set_policy do
    given {|user, session| session && session[:rubric_assessment_ids] && session[:rubric_assessment_ids].include?(self.id) }
    set { can :create and can :read and can :update }
  
    given {|user, session| user && self.assessor_id == user.id }
    set { can :create and can :read and can :update }
    
    given {|user, session| user && self.user_id == user.id }
    set { can :read }
    
    given {|user, session| self.rubric_association && self.rubric_association.grants_rights?(user, session, :manage)[:manage] }
    set { can :create and can :read and can :delete}

    given {|user, session| 
      self.rubric_association && 
      self.rubric_association.grants_rights?(user, session, :manage)[:manage] &&
      (self.rubric_association.association.context.grants_right?(self.assessor, nil, :manage_grades) rescue false)
    }
    set { can :update }
  end
  
  named_scope :of_type, lambda {|type|
    {:conditions => ['rubric_assessments.assessment_type = ?', type.to_s]}
  }
  
  def methods_for_serialization(*methods)
    @serialization_methods = methods
  end
  
  def assessor_name
    self.assessor.name rescue "Unknown User"
  end
  
  def assessment_url
    self.artifact.url rescue nil
  end
  
  def ratings
    self.data
  end
  
  def related_group_submissions_and_assessments
    if self.rubric_association && self.rubric_association.association.is_a?(Assignment) && !self.rubric_association.association.grade_group_students_individually 
      students = self.rubric_association.association.group_students(self.user).last
      submissions = students.map do |student|
        submission = self.rubric_association.association.find_asset_for_assessment(self.rubric_association, student.id).first
        {:submission => submission, :rubric_assessments => submission.rubric_assessments}
      end
    else
      []
    end
  end
  
end
