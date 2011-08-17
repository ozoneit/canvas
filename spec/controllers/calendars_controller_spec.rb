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

describe CalendarsController do
  def course_event(date=nil)
    date = Date.parse(date) if date
    @event = @course.calendar_events.create(:title => "some assignment", :start_at => date, :end_at => date)
  end

  describe "GET 'show'" do
    it "should redirect if no contexts are found" do
      course_with_student(:active_all => true)
      course_event
      get 'show', :course_id => @course.id
      assigns[:contexts].should be_blank
      response.should be_redirect
    end
    
    it "should assign variables" do
      course_with_student_logged_in(:active_all => true)
      course_event
      get 'show', :user_id => @user.id
      response.should be_success
      assigns[:contexts].should_not be_nil
      assigns[:contexts].should_not be_empty
      assigns[:contexts][0].should eql(@user)
      assigns[:contexts][1].should eql(@course)
      assigns[:events].should_not be_nil
      assigns[:undated_events].should_not be_nil
    end
    
    it "should retrieve multiple contexts for user" do
      course_with_student_logged_in(:active_all => true)
      course_event
      e = @user.calendar_events.create(:title => "my event")
      get 'show', :user_id => @user.id, :include_undated => true
      response.should be_success
      assigns[:contexts].should_not be_nil
      assigns[:contexts].should_not be_empty
      assigns[:contexts].length.should eql(2)
      assigns[:contexts][0].should eql(@user)
      assigns[:contexts][1].should eql(@course)
    end
    
    it "should retrieve events for a given month and year" do
      course_with_student_logged_in(:active_all => true)
      e1 = course_event("Jan 1 2008")
      e2 = course_event("Feb 15 2008")
      get 'show', :month => "01", :year => "2008" #, :course_id => @course.id, :month => "01", :year => "2008"
      response.should be_success
      
      get 'show', :month => "02", :year => "2008"
      response.should be_success
    end
  end
  
  describe "GET 'public_feed'" do
    it "should assign variables" do
      course_with_student(:active_all => true)
      course_event
      @course.is_public = true
      @course.save!
      @course.assignments.create!(:title => "some assignment")
      get 'public_feed', :feed_code => "course_#{@course.uuid}"
      response.should be_success
      assigns[:events].should_not be_nil
      assigns[:events].should_not be_empty
      assigns[:events][0].should eql(@event)
    end
      
    it "should assign variables" do
      course_with_student(:active_all => true)
      course_event
      @course.is_public = true
      @course.save!
      @course.assignments.create!(:title => "some assignment")
      
      e = @user.calendar_events.create(:title => "my event")
      get 'public_feed', :feed_code => "user_#{@user.uuid}"
      response.should be_success
      assigns[:events].should_not be_nil
      assigns[:events].should_not be_empty
      assigns[:events].should be_include(e)
    end
  end
end
