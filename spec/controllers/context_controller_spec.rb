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

describe ContextController do
  describe "GET 'roster'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      get 'roster', :course_id => @course.id
      assert_unauthorized
    end
    
    it "should assign variables" do
      course_with_student_logged_in(:active_all => true)
      get 'roster', :course_id => @course.id
      assigns[:students].should_not be_nil
      assigns[:teachers].should_not be_nil
    end
    
    it "should retrieve students and teachers" do
      course_with_student_logged_in(:active_all => true)
      @student = @user
      @teacher = user(:active_all => true)
      @teacher = @course.enroll_teacher(@teacher)
      @teacher.accept!
      @teacher = @teacher.user
      get 'roster', :course_id => @course.id
      assigns[:students].should_not be_nil
      assigns[:students].should_not be_empty
      assigns[:students].should be_include(@student) #[0].should eql(@user)
      assigns[:teachers].should_not be_nil
      assigns[:teachers].should_not be_empty
      assigns[:teachers].should be_include(@teacher) #[0].should eql(@teacher)
    end
  end
  
  describe "GET 'roster_user'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      get 'roster_user', :course_id => @course.id, :id => @user.id
      assert_unauthorized
    end
    
    it "should assign variables" do
      course_with_student_logged_in(:active_all => true)
      @enrollment = @course.enroll_student(user(:active_all => true))
      @enrollment.accept!
      @student = @enrollment.user
      get 'roster_user', :course_id => @course.id, :id => @student.id
      assigns[:enrollment].should_not be_nil
      assigns[:enrollment].should eql(@enrollment)
      assigns[:user].should_not be_nil
      assigns[:user].should eql(@student)
      assigns[:topics].should_not be_nil
      assigns[:entries].should_not be_nil
    end
  end
  
  describe "GET 'chat'" do
    it "should redirect if no chats enabled" do
      course_with_teacher(:active_all => true)
      get 'chat', :course_id => @course.id, :id => @user.id
      response.should be_redirect
    end
    
    it "should require authorization" do
      Tinychat.instance_variable_set('@config', {})
      course_with_teacher(:active_all => true)
      get 'chat', :course_id => @course.id, :id => @user.id
      assert_unauthorized
      Tinychat.instance_variable_set('@config', nil)
    end
    
    it "should redirect 'disabled', if disabled by the teacher" do
      Tinychat.instance_variable_set('@config', {})
      course_with_student_logged_in(:active_all => true)
      @course.update_attribute(:tab_configuration, [{'id'=>9,'hidden'=>true}])
      get 'chat', :course_id => @course.id
      response.should be_redirect
      flash[:notice].should match(/That page has been disabled/)
      Tinychat.instance_variable_set('@config', nil)
    end
    
  end
end