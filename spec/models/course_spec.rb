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

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe Course do
  before(:each) do
    @course = Course.new
  end
  
  context "validation" do
    it "should create a new instance given valid attributes" do
      course_model
    end
  end
  
  it "should create a unique course." do
    @course = Course.create_unique
    @course.name.should eql("My Course")
    @uuid = @course.uuid
    @course2 = Course.create_unique(@uuid)
    @course.should eql(@course2)
  end
  
  it "should always have a uuid, if it was created" do
    @course.save!
    @course.uuid.should_not be_nil
  end
end

describe Course, "account" do
  before(:each) do
    @account = mock_model(Account)
    @account2 = mock_model(Account)
    @course = Course.new
  end
  
  it "should refer to the course's account" do
    @course.account = @account
    @course.account.should eql(@account)
  end
  
  it "should be sortable" do
    3.times {|x| Course.create(:name => x.to_s)}
    lambda{Course.find(:all).sort}.should_not raise_error
  end
end

describe Course, "enroll" do
  
  before(:each) do
    @course = Course.create(:name => "some_name")
    @user = user_with_pseudonym
  end
  
  it "should be able to enroll a student" do
    @course.enroll_student(@user)
    @se = @course.student_enrollments.first
    @se.user_id.should eql(@user.id)
    @se.course_id.should eql(@course.id)
  end
  
  it "should be able to enroll a TA" do
    @course.enroll_ta(@user)
    @tae = @course.ta_enrollments.first
    @tae.user_id.should eql(@user.id)
    @tae.course_id.should eql(@course.id)
  end
  
  it "should be able to enroll a teacher" do
    @course.enroll_teacher(@user)
    @te = @course.teacher_enrollments.first
    @te.user_id.should eql(@user.id)
    @te.course_id.should eql(@course.id)
  end
  
  it "should enroll a student as creation_pending if the course isn't published" do
    @se = @course.enroll_student(@user)
    @se.user_id.should eql(@user.id)
    @se.course_id.should eql(@course.id)
    @se.should be_creation_pending
  end
  
  it "should enroll a teacher as invited if the course isn't published" do
    Notification.create(:name => "Enrollment Registration", :category => "registration")
    @tae = @course.enroll_ta(@user)
    @tae.user_id.should eql(@user.id)
    @tae.course_id.should eql(@course.id)
    @tae.should be_invited
    @tae.messages_sent.should be_include("Enrollment Registration")
  end
  
  it "should enroll a ta as invited if the course isn't published" do
    Notification.create(:name => "Enrollment Registration", :category => "registration")
    @te = @course.enroll_teacher(@user)
    @te.user_id.should eql(@user.id)
    @te.course_id.should eql(@course.id)
    @te.should be_invited
    @te.messages_sent.should be_include("Enrollment Registration")
  end
end

describe Course, "gradebook_to_csv" do
  it "should generate gradebook csv" do
    course_with_student(:active_all => true)
    @group = @course.assignment_groups.create!(:name => "Some Assignment Group", :group_weight => 100)
    @assignment = @course.assignments.create!(:title => "Some Assignment", :points_possible => 10, :assignment_group => @group)
    @assignment.grade_student(@user, :grade => "10")
    @assignment2 = @course.assignments.create!(:title => "Some Assignment 2", :points_possible => 10, :assignment_group => @group)
    @course.recompute_student_scores
    @user.reload
    @course.reload
    
    csv = @course.gradebook_to_csv
    csv.should_not be_nil
    rows = FasterCSV.parse(csv)
    rows.length.should equal(3)
    rows[0][-1].should == "Final Score"
    rows[1][-1].should == "(read only)"
    rows[2][-1].should == "50"
    rows[0][-2].should == "Current Score"
    rows[1][-2].should == "(read only)"
    rows[2][-2].should == "100"
  end
end

describe Course, "merge_into" do
  it "should merge in another course" do
    @c = Course.create!(:name => "some course")
    @c.wiki.wiki_pages.length.should == 1
    @c2 = Course.create!(:name => "another course")
    g = @c2.assignment_groups.create!(:name => "some group")
    due = Time.parse("Jan 1 2000 5:00pm")
    @c2.assignments.create!(:title => "some assignment", :assignment_group => g, :due_at => due)
    @c2.wiki.wiki_pages.create!(:title => "some page")
    @c2.quizzes.create!(:title => "some quiz")
    @c.assignments.length.should eql(0)
    @c.merge_in(@c2, :everything => true)
    @c.reload
    @c.assignment_groups.length.should eql(1)
    @c.assignment_groups.last.name.should eql(@c2.assignment_groups.last.name)
    @c.assignment_groups.last.should_not eql(@c2.assignment_groups.last)
    @c.assignments.length.should eql(1)
    @c.assignments.last.title.should eql(@c2.assignments.last.title)
    @c.assignments.last.should_not eql(@c2.assignments.last)
    @c.assignments.last.due_at.should eql(@c2.assignments.last.due_at)
    @c.wiki.wiki_pages.length.should eql(2)
    @c.wiki.wiki_pages.map(&:title).include?(@c2.wiki.wiki_pages.last.title).should be_true
    @c.wiki.wiki_pages.first.should_not eql(@c2.wiki.wiki_pages.last)
    @c.wiki.wiki_pages.last.should_not eql(@c2.wiki.wiki_pages.last)
    @c.quizzes.length.should eql(1)
    @c.quizzes.last.title.should eql(@c2.quizzes.last.title)
    @c.quizzes.last.should_not eql(@c2.quizzes.last)
  end
  
  it "should update due dates for date changes" do
    new_start = Date.parse("Jun 1 2000")
    new_end = Date.parse("Sep 1 2000")
    @c = Course.create!(:name => "some course", :start_at => new_start, :conclude_at => new_end)
    @c2 = Course.create!(:name => "another course", :start_at => Date.parse("Jan 1 2000"), :conclude_at => Date.parse("Mar 1 2000"))
    g = @c2.assignment_groups.create!(:name => "some group")
    @c2.assignments.create!(:title => "some assignment", :assignment_group => g, :due_at => Time.parse("Jan 3 2000 5:00pm"))
    @c.assignments.length.should eql(0)
    @c2.calendar_events.create!(:title => "some event", :start_at => Time.parse("Jan 11 2000 3:00pm"), :end_at => Time.parse("Jan 11 2000 4:00pm"))
    @c.calendar_events.length.should eql(0)
    @c.merge_in(@c2, :everything => true, :shift_dates => true)
    @c.reload
    @c.assignments.length.should eql(1)
    @c.assignments.last.title.should eql(@c2.assignments.last.title)
    @c.assignments.last.should_not eql(@c2.assignments.last)
    @c.assignments.last.due_at.should > new_start
    @c.assignments.last.due_at.should < new_end
    @c.assignments.last.due_at.hour.should eql(@c2.assignments.last.due_at.hour)
    @c.calendar_events.length.should eql(1)
    @c.calendar_events.last.title.should eql(@c2.calendar_events.last.title)
    @c.calendar_events.last.should_not eql(@c2.calendar_events.last)
    @c.calendar_events.last.start_at.should > new_start
    @c.calendar_events.last.start_at.should < new_end
    @c.calendar_events.last.start_at.hour.should eql(@c2.calendar_events.last.start_at.hour)
    @c.calendar_events.last.end_at.should > new_start
    @c.calendar_events.last.end_at.should < new_end
    @c.calendar_events.last.end_at.hour.should eql(@c2.calendar_events.last.end_at.hour)
  end
  
  it "should match times for changing due dates in a different time zone" do
    Time.zone = "Mountain Time (US & Canada)"
    new_start = Date.parse("Jun 1 2000")
    new_end = Date.parse("Sep 1 2000")
    @c = Course.create!(:name => "some course", :start_at => new_start, :conclude_at => new_end)
    @c2 = Course.create!(:name => "another course", :start_at => Date.parse("Jan 1 2000"), :conclude_at => Date.parse("Mar 1 2000"))
    g = @c2.assignment_groups.create!(:name => "some group")
    @c2.assignments.create!(:title => "some assignment", :assignment_group => g, :due_at => Time.parse("Jan 3 2000 5:00pm"))
    @c.assignments.length.should eql(0)
    @c2.calendar_events.create!(:title => "some event", :start_at => Time.parse("Jan 11 2000 3:00pm"), :end_at => Time.parse("Jan 11 2000 4:00pm"))
    @c.calendar_events.length.should eql(0)
    @c.merge_in(@c2, :everything => true, :shift_dates => true)
    @c.reload
    @c.assignments.length.should eql(1)
    @c.assignments.last.title.should eql(@c2.assignments.last.title)
    @c.assignments.last.should_not eql(@c2.assignments.last)
    @c.assignments.last.due_at.should > new_start
    @c.assignments.last.due_at.should < new_end
    @c.assignments.last.due_at.wday.should eql(@c2.assignments.last.due_at.wday)
    @c.assignments.last.due_at.utc.hour.should eql(@c2.assignments.last.due_at.utc.hour)
    @c.calendar_events.length.should eql(1)
    @c.calendar_events.last.title.should eql(@c2.calendar_events.last.title)
    @c.calendar_events.last.should_not eql(@c2.calendar_events.last)
    @c.calendar_events.last.start_at.should > new_start
    @c.calendar_events.last.start_at.should < new_end
    @c.calendar_events.last.start_at.wday.should eql(@c2.calendar_events.last.start_at.wday)
    @c.calendar_events.last.start_at.utc.hour.should eql(@c2.calendar_events.last.start_at.utc.hour)
    @c.calendar_events.last.end_at.should > new_start
    @c.calendar_events.last.end_at.should < new_end
    @c.calendar_events.last.end_at.wday.should eql(@c2.calendar_events.last.end_at.wday)
    @c.calendar_events.last.end_at.utc.hour.should eql(@c2.calendar_events.last.end_at.utc.hour)
    Time.zone = nil
  end
end

describe Course, "update_account_associations" do
  it "should update account associations correctly" do
    account1 = Account.create!(:name => 'first')
    account2 = Account.create!(:name => 'second')
    
    @c = Course.create!(:account => account1)
    @c.associated_accounts.length.should eql(1)
    @c.associated_accounts.first.should eql(account1)
    
    @c.account = account2
    @c.save!
    @c.reload
    @c.associated_accounts.length.should eql(1)
    @c.associated_accounts.first.should eql(account2)
  end
end

describe Course, "tabs_available" do
  it "should return the defaults if nothing specified" do
    course_with_teacher(:active_all => true)
    length = Course.default_tabs.length
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should eql(Course.default_tabs.map{|t| t[:id] })
    tab_ids.length.should eql(length)
  end
  
  it "should overwrite the order of tabs if configured" do
    course_with_teacher(:active_all => true)
    length = Course.default_tabs.length
    @course.tab_configuration = [{'id' => Course::TAB_COLLABORATIONS}, {'id' => Course::TAB_CHAT}]
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should eql(([Course::TAB_COLLABORATIONS, Course::TAB_CHAT] + Course.default_tabs.map{|t| t[:id] }).uniq)
    tab_ids.length.should eql(length)
  end
  
  it "should remove ids for tabs not in the default list" do
    course_with_teacher(:active_all => true)
    @course.tab_configuration = [{'id' => 912}]
    @course.tabs_available(@user).map{|t| t[:id] }.should_not be_include(912)
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should eql(Course.default_tabs.map{|t| t[:id] })
    tab_ids.length.should > 0
    @course.tabs_available(@user).map{|t| t[:label] }.compact.length.should eql(tab_ids.length)
  end
  
  it "should hide unused tabs if not an admin" do
    course_with_student(:active_all => true)
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should_not be_include(Course::TAB_SETTINGS)
    tab_ids.length.should > 0
  end
  
  it "should show grades tab for students" do
    course_with_student(:active_all => true)
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should be_include(Course::TAB_GRADES)
  end
  
  it "should not show grades tab for observers" do
    course_with_student(:active_all => true)
    @student = @user
    user(:active_all => true)
    @oe = @course.enroll_user(@user, 'ObserverEnrollment')
    @oe.accept
    @user.reload
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should_not be_include(Course::TAB_GRADES)
  end
    
  it "should show grades tab for observers if they are linked to a student" do
    course_with_student(:active_all => true)
    @student = @user
    user(:active_all => true)
    @oe = @course.enroll_user(@user, 'ObserverEnrollment')
    @oe.accept
    @oe.associated_user_id = @student.id
    @oe.save!
    @user.reload
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should be_include(Course::TAB_GRADES)
  end
end

describe Course, "backup" do
  it "should backup to a valid data structure" do
    course_to_backup
    data = @course.backup
    data.should_not be_nil
    data.length.should > 0
    data.any?{|i| i.is_a?(Assignment)}.should eql(true)
    data.any?{|i| i.is_a?(WikiPage)}.should eql(true)
    data.any?{|i| i.is_a?(DiscussionTopic)}.should eql(true)
    data.any?{|i| i.is_a?(CalendarEvent)}.should eql(true)
  end
  
  it "should backup to a valid json string" do
    course_to_backup
    data = @course.backup_to_json
    data.should_not be_nil
    data.length.should > 0
    parse = JSON.parse(data) rescue nil
    parse.should_not be_nil
    parse.should be_is_a(Array)
    parse.length.should > 0
  end
    
  context "merge_into_course" do
    it "should merge content into another course" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :everything => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should_not be_nil
      @new_topic = @new_course.discussion_topics.find_by_cloned_item_id(@old_topic.cloned_item_id)
      @new_topic.should_not be_nil
      html = @new_topic.message
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end
    
    it "should merge onlys selected content into another course" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :all_files => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should be_nil
      @new_course.discussion_topics.count.should eql(0)
    end

    it "should merge implied content into another course" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :all_topics => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should_not be_nil
      @new_topic = @new_course.discussion_topics.find_by_cloned_item_id(@old_topic.cloned_item_id)
      @new_topic.should_not be_nil
      html = @new_topic.message
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end

    it "should translate links to the new context" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_attachment = @old_attachment.clone_for(@new_course)
      @new_attachment.save!
      html = Course.migrate_content_links(@old_topic.message, @old_course, @new_course)
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end
    
    it "should bring over linked files if not already brought over" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      html = Course.migrate_content_links(@old_topic.message, @old_course, @new_course)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end

    it "should assign the correct parent folder when the parent folder has already been created" do
      old_course = course_model
      folder = Folder.root_folders(@course).first
      folder = folder.sub_folders.create!(:context => @course, :name => 'folder_1')
      attachment_model(:folder => folder, :filename => "dummy.txt")
      folder = folder.sub_folders.create!(:context => @course, :name => 'folder_2')
      folder = folder.sub_folders.create!(:context => @course, :name => 'folder_3')
      old_attachment = attachment_model(:folder => folder, :filename => "merge.test")

      new_course = course_model

      new_course.merge_into_course(old_course, :everything => true)
      old_attachment.reload
      old_attachment.cloned_item_id.should_not be_nil
      new_attachment = new_course.attachments.find_by_cloned_item_id(old_attachment.cloned_item_id)
      new_attachment.should_not be_nil
      new_attachment.full_path.should == "course files/folder_1/folder_2/folder_3/merge.test"
      folder.reload
      new_attachment.folder.cloned_item_id.should == folder.cloned_item_id
    end
  end
end
def course_to_backup
  @course = course
  group = @course.assignment_groups.create!(:name => "Some Assignment Group")
  @course.assignments.create!(:title => "Some Assignment", :assignment_group => group)
  @course.calendar_events.create!(:title => "Some Event", :start_at => Time.now, :end_at => Time.now)
  @course.wiki.wiki_pages.create!(:title => "Some Page")
  topic = @course.discussion_topics.create!(:title => "Some Discussion")
  topic.discussion_entries.create!(:message => "just a test")
  @course
end
