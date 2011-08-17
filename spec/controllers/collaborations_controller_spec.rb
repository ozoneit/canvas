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

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe CollaborationsController do
  before(:all) do
    EtherpadCollaboration.instance_variable_set('@config', {'domain' => 'typewith.me', 'name' => 'EtherPad'})
  end
  describe "GET 'index'" do
    it "should require authorization" do
      course_with_student(:active_all => true)
      get 'index', :course_id => @course.id
      assert_unauthorized
    end
    
    it "should redirect 'disabled', if disabled by the teacher" do
      course_with_student_logged_in(:active_all => true)
      @course.update_attribute(:tab_configuration, [{'id'=>16,'hidden'=>true}])
      get 'index', :course_id => @course.id
      response.should be_redirect
      flash[:notice].should match(/That page has been disabled/)
    end
    
    it "should assign variables" do
      course_with_student_logged_in(:active_all => true)
      get 'index', :course_id => @course.id
      response.should be_success
    end
    
  end
  
  describe "POST 'create'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      post 'create', :course_id => @course.id, :collaboration => {}
      assert_unauthorized
    end
    
    it "should fail with invalid collaboration type" do
      course_with_teacher_logged_in(:active_all => true)
      rescue_action_in_public!
      post 'create', :course_id => @course.id, :collaboration => {:title => "My Collab"}
      assert_status(500)
    end
    
    it "should create collaboration" do
      course_with_teacher_logged_in(:active_all => true)
      post 'create', :course_id => @course.id, :collaboration => {:collaboration_type => 'EtherPad', :title => "My Collab"}
      response.should be_redirect
      assigns[:collaboration].should_not be_nil
      assigns[:collaboration].class.should eql(EtherpadCollaboration)
      assigns[:collaboration].collaboration_type.should eql('EtherPad')
      Collaboration.find(assigns[:collaboration].id).should be_is_a(EtherpadCollaboration)
    end
    
  end
end
