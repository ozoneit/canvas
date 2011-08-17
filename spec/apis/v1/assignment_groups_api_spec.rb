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

require File.expand_path(File.dirname(__FILE__) + '/../api_spec_helper')

describe AssignmentGroupsController, :type => :integration do
  it "should sort the returned list of assignment groups" do
    # the API returns the assignments sorted by
    # assignment_groups.position
    course_with_teacher_logged_in(:active_all => true)
    group1 = @course.assignment_groups.create!(:name => 'group1')
    group1.update_attribute(:position, 10)
    group2 = @course.assignment_groups.create!(:name => 'group2')
    group2.update_attribute(:position, 7)
    group3 = @course.assignment_groups.create!(:name => 'group3')
    group3.update_attribute(:position, 12)

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignment_groups.json",
          { :controller => 'assignment_groups', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s })

    json.should == [
      {
        'id' => group2.id,
        'name' => 'group2',
        'position' => 7,
      },
      {
        'id' => group1.id,
        'name' => 'group1',
        'position' => 10,
      },
      {
        'id' => group3.id,
        'name' => 'group3',
        'position' => 12,
      },
    ]
  end

  it "should include full assignment jsonification when specified" do
    course_with_teacher_logged_in(:active_all => true)
    group1 = @course.assignment_groups.create!(:name => 'group1')
    group1.update_attribute(:position, 10)
    group2 = @course.assignment_groups.create!(:name => 'group2')
    group2.update_attribute(:position, 7)

    a1 = @course.assignments.create!(:title => "test1", :assignment_group => group1, :points_possible => 10)
    a2 = @course.assignments.create!(:title => "test2", :assignment_group => group1, :points_possible => 12)
    a3 = @course.assignments.create!(:title => "test3", :assignment_group => group2, :points_possible => 8)
    a4 = @course.assignments.create!(:title => "test4", :assignment_group => group2, :points_possible => 9)

    rubric_model(:user => @user, :context => @course,
                                     :data => larger_rubric_data)

    a3.create_rubric_association(:rubric => @rubric, :purpose => 'grading', :use_for_grading => true)

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignment_groups.json?include[]=assignments",
          { :controller => 'assignment_groups', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s,
            :include => ['assignments'] })

    json.should == [
      {
        'id' => group2.id,
        'name' => 'group2',
        'position' => 7,
        'assignments' => [
          {
            'id' => a3.id,
            'name' => 'test3',
            'position' => 1,
            'points_possible' => 8,
            'needs_grading_count' => 0,
            "submission_types" => [
              "none",
            ],
            'grading_type' => 'points',
            'use_rubric_for_grading' => true,
            'free_form_criterion_comments' => false,
            'rubric' => [
              {'id' => 'crit1', 'points' => 10, 'description' => 'Crit1',
                'ratings' => [
                  {'id' => 'rat1', 'points' => 10, 'description' => 'A'},
                  {'id' => 'rat2', 'points' => 7, 'description' => 'B'},
                  {'id' => 'rat3', 'points' => 0, 'description' => 'F'},
                ],
              },
              {'id' => 'crit2', 'points' => 2, 'description' => 'Crit2',
                'ratings' => [
                  {'id' => 'rat1', 'points' => 2, 'description' => 'Pass'},
                  {'id' => 'rat2', 'points' => 0, 'description' => 'Fail'},
                ],
              },
            ],
          },
          {
            'id' => a4.id,
            'name' => 'test4',
            'position' => 2,
            'points_possible' => 9,
            'needs_grading_count' => 0,
            "submission_types" => [
              "none",
            ],
            'grading_type' => 'points',
          },
        ],
      },
      {
        'id' => group1.id,
        'name' => 'group1',
        'position' => 10,
        'assignments' => [
          {
            'id' => a1.id,
            'name' => 'test1',
            'position' => 1,
            'points_possible' => 10,
            'needs_grading_count' => 0,
            "submission_types" => [
              "none",
            ],
            'grading_type' => 'points',
          },
          {
            'id' => a2.id,
            'name' => 'test2',
            'position' => 2,
            'points_possible' => 12,
            'needs_grading_count' => 0,
            "submission_types" => [
              "none",
            ],
            'grading_type' => 'points',
          },
        ],
      },
    ]
  end

  it "should exclude deleted assignments" do
    course_with_teacher_logged_in(:active_all => true)
    group1 = @course.assignment_groups.create!(:name => 'group1')
    group1.update_attribute(:position, 10)

    a1 = @course.assignments.create!(:title => "test1", :assignment_group => group1, :points_possible => 10)
    a2 = @course.assignments.create!(:title => "test2", :assignment_group => group1, :points_possible => 12)
    a2.reload
    a2.destroy

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignment_groups.json?include[]=assignments",
          { :controller => 'assignment_groups', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s,
            :include => ['assignments'] })

    group = json.first
    group.should be_present
    group['assignments'].size.should == 1
    group['assignments'].first['name'].should == 'test1'
  end
end
