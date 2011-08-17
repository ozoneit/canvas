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

describe Assignment do
  it "should create a new instance given valid attributes" do
    setup_assignment
    @c.assignments.create!(assignment_valid_attributes)
  end
  
  it "should have a useful state machine" do
    assignment_model
    @a.state.should eql(:published)
    @a.unpublish
    @a.state.should eql(:available)
  end
  
  it "should be able to submit homework" do
    setup_assignment_with_homework
    @assignment.submissions.size.should eql(1)
    @submission = @assignment.submissions.first
    @submission.user_id.should eql(@user.id)
  end
  
  it "should be able to grade a submission" do
    setup_assignment_without_submission
    s = @assignment.grade_student(@user, :grade => "10")
    s.should be_is_a(Array)
    @assignment.reload
    @assignment.submissions.size.should eql(1)
    @submission = @assignment.submissions.first
    @submission.state.should eql(:graded)
    @submission.should eql(s[0])
    @submission.score.should eql(10.0)
    @submission.user_id.should eql(@user.id)
  end

  it "should update needs_grading_count when submissions transition state" do
    setup_assignment_with_homework
    @assignment.needs_grading_count.should eql(1)
    @assignment.grade_student(@user, :grade => "0")
    @assignment.reload
    @assignment.needs_grading_count.should eql(0)
  end
  
  it "should update needs_grading_count when enrollment changes" do
    setup_assignment_with_homework
    @assignment.needs_grading_count.should eql(1)
    @course.enrollments.find_by_user_id(@user.id).destroy
    @assignment.reload
    @assignment.needs_grading_count.should eql(0)
    e = @course.enroll_student(@user)
    e.invite
    e.accept
    @assignment.reload
    @assignment.needs_grading_count.should eql(1)
  end
  
  it "should not override the grade if the assignment has no points possible" do
    setup_assignment_without_submission
    @assignment.grading_type = 'pass_fail'
    @assignment.points_possible = 0
    @assignment.save
    s = @assignment.grade_student(@user, :grade => "pass")
    s.should be_is_a(Array)
    @assignment.reload
    @assignment.submissions.size.should eql(1)
    @submission = @assignment.submissions.first
    @submission.state.should eql(:graded)
    @submission.should eql(s[0])
    @submission.score.should eql(0.0)
    @submission.grade.should eql("pass")
    @submission.user_id.should eql(@user.id)
  end
  
  it "should be able to grade an already-existing submission" do
    setup_assignment_without_submission

    s = @a.submit_homework(@user)
    s2 = @a.grade_student(@user, :grade => "10")
    s.reload
    s.should eql(s2[0])
    s2[0].state.should eql(:graded)
  end
  
  it "should be versioned" do
    assignment_model
    @a.should be_respond_to(:versions)
  end

  describe "infer_due_at" do
    it "should set to all_day" do
      assignment_model(:due_at => "Sep 3 2008 12:00am")
      @assignment.all_day.should eql(false)
      @assignment.infer_due_at
      @assignment.save!
      @assignment.all_day.should eql(true)
      @assignment.due_at.strftime("%H:%M").should eql("23:59")
      @assignment.all_day_date.should eql(Date.parse("Sep 3 2008"))
    end

    it "should not set to all_day without infer_due_at call" do
      assignment_model(:due_at => "Sep 3 2008 12:00am")
      @assignment.all_day.should eql(false)
      @assignment.due_at.strftime("%H:%M").should eql("00:00")
      @assignment.all_day_date.should eql(Date.parse("Sep 3 2008"))
    end
  end

  it "should treat 11:59pm as an all_day" do
    assignment_model(:due_at => "Sep 4 2008 11:59pm")
    @assignment.all_day.should eql(true)
    @assignment.due_at.strftime("%H:%M").should eql("23:59")
    @assignment.all_day_date.should eql(Date.parse("Sep 4 2008"))
  end

  it "should not be set to all_day if a time is specified" do
    assignment_model(:due_at => "Sep 4 2008 11:58pm")
    @assignment.all_day.should eql(false)
    @assignment.due_at.strftime("%H:%M").should eql("23:58")
    @assignment.all_day_date.should eql(Date.parse("Sep 4 2008"))
  end

  context "peer reviews" do
    it "should assign peer reviews" do
      setup_assignment
      assignment_model

      @submissions = []
      # log = Logger.new(STDOUT)
      # n = Time.now
      # log.info('adding students')
      users = []
      10.times do |i|
        users << User.create(:name => "user #{i}")
      end
      # log.info("enrolling #{Time.now - n}")
      # n = Time.now
      users.each do |u|
        @c.enroll_user(u)
      end
      # log.info("adding submissions #{Time.now - n}")
      # n = Time.now
      users.each do |u|
        @submissions << @a.submit_homework(u, :submission_type => "online_url", :url => "http://www.google.com")
      end
      # log.info("assigning peer reviews #{Time.now - n}")
      # n = Time.now
      @a.peer_review_count = 1
      res = @a.assign_peer_reviews
      # log.info("done assigning peer reviews #{Time.now - n}")
      res.length.should eql(@submissions.length)
      @submissions.each do |s|
        res.map{|a| a.asset}.should be_include(s)
        res.map{|a| a.assessor_asset}.should be_include(s)
      end
    end
    
    it "should assign multiple peer reviews" do
      setup_assignment
      assignment_model
      
      @submissions = []
      3.times do |i|
        e = @c.enroll_user(User.create(:name => "user #{i}"))
        @submissions << @a.submit_homework(e.user, :submission_type => "online_url", :url => "http://www.google.com")
      end
      @a.peer_review_count = 2
      res = @a.assign_peer_reviews
      res.length.should eql(@submissions.length * 2)
      @submissions.each do |s|
        assets = res.select{|a| a.asset == s}
        assets.length.should be > 0 #eql(2)
        assets.map{|a| a.assessor_id}.uniq.length.should eql(assets.length)

        assessors = res.select{|a| a.assessor_asset == s}
        assessors.length.should eql(2)
        assessors[0].asset_id.should_not eql(assessors[1].asset_id)
      end
    end

    it "should assign late peer reviews" do
      setup_assignment
      assignment_model
      
      @submissions = []
      5.times do |i|
        e = @c.enroll_user(User.create(:name => "user #{i}"))
        @submissions << @a.submit_homework(e.user, :submission_type => "online_url", :url => "http://www.google.com")
      end
      @a.peer_review_count = 2
      res = @a.assign_peer_reviews
      res.length.should eql(@submissions.length * 2)
      # @submissions.each do |s|
        # # This user should have two unique assessors assigned
        # assets = res.select{|a| a.asset == s}
        # assets.length.should be > 0 #eql(2)
        # assets.map{|a| a.assessor_id}.uniq.length.should eql(assets.length)
        
        # # This user should be assigned two unique submissions to assess
        # assessors = res.select{|a| a.assessor_asset == s}
        # assessors.length.should eql(2)
        # assessors[0].asset_id.should_not eql(assessors[1].asset_id)
      # end
      e = @c.enroll_user(User.create(:name => "new user"))
      @a.reload
      s = @a.submit_homework(e.user, :submission_type => "online_url", :url => "http://www.google.com")
      res = @a.assign_peer_reviews
      res.length.should >= 2
      res.any?{|a| a.assessor_asset == s}.should eql(true)
    end
    
    it "should assign late peer reviews to each other if there is more than one" do
      setup_assignment
      assignment_model
      
      @submissions = []
      10.times do |i|
        e = @c.enroll_user(User.create(:name => "user #{i}"))
        @submissions << @a.submit_homework(e.user, :submission_type => "online_url", :url => "http://www.google.com")
      end
      @a.peer_review_count = 2
      res = @a.assign_peer_reviews
      res.length.should eql(@submissions.length * 2)
      # @submissions.each do |s|
        # assets = res.select{|a| a.asset == s}
        # assets.length.should be > 0 #eql(2)
        # assets.map{|a| a.assessor_id}.uniq.length.should eql(assets.length)
        
        # assessors = res.select{|a| a.assessor_asset == s}
        # assessors.length.should eql(2)
        # assessors[0].asset_id.should_not eql(assessors[1].asset_id)
      # end
      
      @late_submissions = []
      3.times do |i|
        e = @c.enroll_user(User.create(:name => "new user #{i}"))
        @a.reload
        @late_submissions << @a.submit_homework(e.user, :submission_type => "online_url", :url => "http://www.google.com")
      end
      res = @a.assign_peer_reviews
      res.length.should >= 6
      ids = @late_submissions.map{|s| s.user_id}
      # @late_submissions.each do |s|
        # assets = res.select{|a| a.asset == s}
        # assets.length.should be > 0 #eql(2)
        # assets.all?{|a| a.assessor_id != s.user_id && ids.include?(a.assessor_id) }.should eql(true)
        
        # assessor_assets = res.select{|a| a.assessor_asset == s}
        # assessor_assets.length.should eql(2)
        # assets.all?{|a| a.assessor_id != s.user_id && ids.include?(a.assessor_id) }.should eql(true)
      # end
    end
  end
  
  context "publishing" do
    it "should publish automatically if set that way" do
      course_model(:publish_grades_immediately => true)
      @course.offer!
      @enr1 = @course.enroll_student(@stu1 = user)
      @enr2 = @course.enroll_student(@stu2 = user)
      @assignment = @course.assignments.create(:title => "asdf", :points_possible => 10)
      @assignment.should be_published
      @sub1 = @assignment.grade_student(@stu1, :grade => 9).first
      @sub1.score.should == 9.0
      @sub1.published_score.should == @sub1.score
    end
    
    it "should NOT publish automatically if set that way" do
      course_model(:publish_grades_immediately => false)
      @course.offer!
      @enr1 = @course.enroll_student(@stu1 = user)
      @enr2 = @course.enroll_student(@stu2 = user)
      @assignment = @course.assignments.create(:title => "asdf", :points_possible => 10)
      @assignment.should_not be_published
      @sub1 = @assignment.grade_student(@stu1, :grade => 9).first
      @sub1.score.to_f.should == 9.0
      @sub1.published_score.should == @sub1.score
      # Took this out until someone asks for it
      # @sub1.published_score.should_not == @sub1.score
    end
    
    it "should publish past submissions when the assignment is published" do
      course_model(:publish_grades_immediately => false)
      @course.offer!
      @enr1 = @course.enroll_student(@stu1 = user)
      @enr2 = @course.enroll_student(@stu2 = user)
      @assignment = @course.assignments.create(:title => "asdf", :points_possible => 10)
      @assignment.should_not be_published
      @sub1 = @assignment.grade_student(@stu1, :grade => 9).first
      @sub1.score.should == 9
      # Took this out until someone asks for it
      # @sub1.published_score.should_not == @sub1.score
      @sub1.published_score.should == @sub1.score
      @assignment.reload
      @assignment.submissions.should be_include(@sub1)
      @assignment.publish!
      @assignment.should be_published
      @sub1.reload
      @sub1.score.should == 9
      @sub1.published_score.should == @sub1.score
    end

    it "should re-publish correctly" do
      course_model(:publish_grades_immediately => false)
      @course.offer!
      @enr1 = @course.enroll_student(@stu1 = user)
      @enr2 = @course.enroll_student(@stu2 = user)
      @assignment = @course.assignments.create(:title => "asdf", :points_possible => 10)
      @assignment.should_not be_published
      @sub1 = @assignment.grade_student(@stu1, :grade => 9).first
      @sub1.score.should == 9
      @sub1.published_score.should == @sub1.score
      # Took this out until someone asks for it
      # @sub1.published_score.should_not == @sub1.score
      @assignment.reload
      @assignment.submissions.should be_include(@sub1)
      @assignment.publish!
      @assignment.should be_published
      @sub1.reload
      @sub1.score.should == 9
      @sub1.published_score.should == @sub1.score
      @assignment.unpublish!
      @assignment.should_not be_published
      @sub1 = @assignment.grade_student(@stu1, :grade => 8).first
      @sub1.score.should == 8
      @sub1.published_score.should == 8
      # Took this out until someone asks for it
      # @sub1.published_score.should == 9
      @sub2 = @assignment.grade_student(@stu2, :grade => 7).first
      @sub2.score.should == 7
      # Took this out until someone asks for it
      # @sub2.published_score.should == nil
      @sub2.published_score.should == 7
      @assignment.reload
      @assignment.submissions.should be_include(@sub2)
      @assignment.publish!
      @assignment.should be_published
      @sub1.reload
      @sub1.score.should == 8
      @sub1.published_score == 8
      @sub2.reload
      @sub2.score.should == 7
      @sub2.published_score.should == 7
    end
    
    it "should fire off assignment graded notification on first publish" do
      setup_unpublished_assignment_with_students
      @assignment.publish!
      @assignment.should be_published
      @assignment.messages_sent.should be_include("Assignment Graded")
      @sub1.messages_sent.should be_empty
    end
    
    it "should fire off submission graded notifications if already published" do
      setup_unpublished_assignment_with_students
      @assignment.publish!
      @assignment.should be_published
      @sub2 = @assignment.grade_student(@stu2, :grade => 8).first
      @sub2.messages_sent.should be_include("Submission Graded")
      @sub2.messages_sent.should_not be_include("Submission Grade Changed")
      @sub2.update_attributes(:graded_at => Time.now - 60*60)
      @sub2 = @assignment.grade_student(@stu2, :grade => 9).first
      @sub2.messages_sent.should_not be_include("Submission Graded")
      @sub2.messages_sent.should be_include("Submission Grade Changed")
    end
    
    it "should not fire off assignment graded notification if started as published" do
      setup_assignment
      Notification.create!(:name => "Assignment Graded")
      @assignment2 = @course.assignments.create(:title => "new assignment")
      @assignment2.workflow_state = 'published'
      @assignment2.messages_sent.should_not be_include("Assignment Graded")
    end
    
    it "should update grades when assignment changes" do
      setup_assignment_without_submission
      @a.update_attributes(:grading_type => 'letter_grade', :points_possible => 20)
      @teacher = @a.context.enroll_user(User.create(:name => "user 1"), 'TeacherEnrollment').user
      @student = @a.context.enroll_user(User.create(:name => "user 1"), 'StudentEnrollment').user

      @sub = @assignment.grade_student(@student, :grader => @teacher, :grade => 'C').first
      @sub.grade.should eql('C')
      @sub.score.should eql(15.2)
      
      @assignment.points_possible = 30
      @assignment.save!
      @sub.reload
      @sub.score.should eql(15.2)
      @sub.grade.should eql('F')
    end
    
    it "should accept lowercase letter grades" do
      setup_assignment_without_submission
      @a.update_attributes(:grading_type => 'letter_grade', :points_possible => 20)
      @teacher = @a.context.enroll_user(User.create(:name => "user 1"), 'TeacherEnrollment').user
      @student = @a.context.enroll_user(User.create(:name => "user 1"), 'StudentEnrollment').user

      @sub = @assignment.grade_student(@student, :grader => @teacher, :grade => 'c').first
      @sub.grade.should eql('C')
      @sub.score.should eql(15.2)
    end
    
    it "should not fire off assignment graded notification on second publish" do
      setup_unpublished_assignment_with_students
      @assignment.publish!
      @assignment.should be_published
      @assignment.messages_sent.should be_include("Assignment Graded")
      @assignment.clear_broadcast_messages
      @assignment.messages_sent.should be_empty
      @assignment.unpublish!
      @assignment.should be_available
      @assignment.messages_sent.should_not be_include("Assignment Graded")
      @assignment.publish!
      @assignment.should be_published
      @assignment.messages_sent.should_not be_include("Assignment Graded")
    end
    
    it "should not fire off submission graded notifications while unpublished" do
      setup_unpublished_assignment_with_students
      @assignment.publish!
      @assignment.should be_published
      @assignment.unpublish!
      @assignment.should be_available
      @sub2 = @assignment.grade_student(@stu2, :grade => 8).first
      @sub2.messages_sent.should be_empty
      @sub2.update_attributes(:graded_at => Time.now - 60*60)
      @sub2 = @assignment.grade_student(@stu2, :grade => 9).first
      @sub2.messages_sent.should be_empty
    end
    
    it" should fire off submission graded notifications on second publish" do
      setup_unpublished_assignment_with_students
      @assignment.publish!
      @assignment.should be_published
      @assignment.clear_broadcast_messages
      @assignment.unpublish!
      @assignment.should be_available
      @assignment.messages_sent.should be_empty
      @sub2 = @assignment.grade_student(@stu2, :grade => 8).first
      @sub2.messages_sent.should be_empty
      @sub2.update_attributes(:graded_at => Time.now - 60*60)
      @assignment.reload
      @assignment.publish!
      @assignment.should be_published
      @assignment.messages_sent.should_not be_include("Assignment Graded")
      @assignment.updated_submissions.should_not be_nil
      @assignment.updated_submissions.should_not be_empty
      @assignment.updated_submissions.sort_by(&:id).first.messages_sent.should be_empty
      @assignment.updated_submissions.sort_by(&:id).last.messages_sent.should be_include("Submission Grade Changed")
    end
  end
  
  context "to_json" do
    it "should include permissions if specified" do
      assignment_model
      @course.offer!
      @enr1 = @course.enroll_teacher(@teacher = user)
      @enr1.accept
      @assignment.to_json.should_not match(/permissions/)
      @assignment.to_json(:permissions => {:user => nil}).should match(/\"permissions\"\s*:\s*\{\}/)
      @assignment.grants_right?(@teacher, nil, :create).should eql(true)
      @assignment.to_json(:permissions => {:user => @teacher, :session => nil}).should match(/\"permissions\"\s*:\s*\{\"/)
      hash = ActiveSupport::JSON.decode(@assignment.to_json(:permissions => {:user => @teacher, :session => nil}))
      hash["assignment"].should_not be_nil
      hash["assignment"]["permissions"].should_not be_nil
      hash["assignment"]["permissions"].should_not be_empty
      hash["assignment"]["permissions"]["read"].should eql(true)
    end
    
    it "should serialize with roots included in nested elements" do
      course_model
      @course.assignments.create!(:title => "some assignment")
      hash = ActiveSupport::JSON.decode(@course.to_json(:include => :assignments))
      hash["course"].should_not be_nil
      hash["course"]["assignments"].should_not be_empty
      hash["course"]["assignments"][0].should_not be_nil
      hash["course"]["assignments"][0]["assignment"].should_not be_nil
    end
    
    it "should serialize with permissions" do
      assignment_model
      @course.offer!
      @enr1 = @course.enroll_teacher(@teacher = user)
      @enr1.accept
      hash = ActiveSupport::JSON.decode(@course.to_json(:permissions => {:user => @teacher, :session => nil} ))
      hash["course"].should_not be_nil
      hash["course"]["permissions"].should_not be_nil
      hash["course"]["permissions"].should_not be_empty
      hash["course"]["permissions"]["read"].should eql(true)
    end
    
    it "should exclude root" do
      assignment_model
      @course.offer!
      @enr1 = @course.enroll_teacher(@teacher = user)
      @enr1.accept
      hash = ActiveSupport::JSON.decode(@course.to_json(:include_root => false, :permissions => {:user => @teacher, :session => nil} ))
      hash["course"].should be_nil
      hash["name"].should eql(@course.name)
      hash["permissions"].should_not be_nil
      hash["permissions"].should_not be_empty
      hash["permissions"]["read"].should eql(true)
    end

  end
  
  context "ical" do
    it ".to_ics should not fail for null due dates" do
      assignment_model(:due_at => "")
      res = @assignment.to_ics
      res.should_not be_nil
      res.match(/DTSTART/).should be_nil
    end
    
    it ".to_ics should not return data for null due dates" do
      assignment_model(:due_at => "")
      res = @assignment.to_ics(false)
      res.should be_nil
    end
    
    it ".to_ics should return string data for assignments with due dates" do
      Account.default.update_attribute(:default_time_zone, 'UTC')
      assignment_model(:due_at => "Sep 3 2008 11:55am")
      res = @assignment.to_ics
      res.should_not be_nil
      res.match(/DTEND:20080903T115500Z/).should_not be_nil
      res.match(/DTSTART:20080903T115500Z/).should_not be_nil
    end

    it ".to_ics should return data for assignments with due dates" do
      Account.default.update_attribute(:default_time_zone, 'UTC')
      assignment_model(:due_at => "Sep 3 2008 11:55am")
      res = @assignment.to_ics(false)
      res.should_not be_nil
      res.start.strftime('%Y-%m-%dT%H:%M:00z').should eql(ActiveSupport::TimeWithZone.new(Time.parse("Sep 3 2008 11:55am"), Time.zone).strftime('%Y-%m-%dT%H:%M:00z'))
      res.end.strftime('%Y-%m-%dT%H:%M:00z').should eql(ActiveSupport::TimeWithZone.new(Time.parse("Sep 3 2008 11:55am"), Time.zone).strftime('%Y-%m-%dT%H:%M:00z'))
    end
    
    it ".to_ics should return string dates for all_day events" do
      Account.default.update_attribute(:default_time_zone, 'UTC')
      assignment_model(:due_at => "Sep 3 2008 11:59pm")
      @assignment.all_day.should eql(true)
      res = @assignment.to_ics
      res.match(/DTSTART;VALUE=DATE:20080903/).should_not be_nil
      res.match(/DTEND;VALUE=DATE:20080903/).should_not be_nil      
    end
  end
  
  context "quizzes and topics" do
    it "should create a quiz if none exists and specified" do
      assignment_model(:submission_types => "online_quiz")
      @a.reload
      @a.submission_types.should eql('online_quiz')
      @a.quiz.should_not be_nil
      @a.quiz.assignment_id.should eql(@a.id)
      @a.due_at = Time.now
      @a.save
      @a.reload
      @a.quiz.should_not be_nil
      @a.quiz.assignment_id.should eql(@a.id)
    end
    
    it "should delete a quiz if no longer specified" do
      assignment_model(:submission_types => "online_quiz")
      @a.reload
      @a.submission_types.should eql('online_quiz')
      @a.quiz.should_not be_nil
      @a.quiz.assignment_id.should eql(@a.id)
      @a.submission_types = 'on_paper'
      @a.save!
      @a.reload
      @a.quiz.should be_nil
    end
    
    it "should create a discussion_topic if none exists and specified" do
      assignment_model(:submission_types => "discussion_topic")
      @a.submission_types.should eql('discussion_topic')
      @a.discussion_topic.should_not be_nil
      @a.discussion_topic.assignment_id.should eql(@a.id)
      @a.due_at = Time.now
      @a.save
      @a.reload
      @a.discussion_topic.should_not be_nil
      @a.discussion_topic.assignment_id.should eql(@a.id)
    end
    
    it "should delete a discussion_topic if no longer specified" do
      assignment_model(:submission_types => "discussion_topic")
      @a.submission_types.should eql('discussion_topic')
      @a.discussion_topic.should_not be_nil
      @a.discussion_topic.assignment_id.should eql(@a.id)
      @a.submission_types = 'on_paper'
      @a.save!
      @a.reload
      @a.discussion_topic.should be_nil
    end
  end

  context "broadcast policy" do
    it "should have a broadcast policy" do
      assignment_model
      @a.should be_respond_to(:dispatch)
      @a.should be_respond_to(:to)
    end
    
    it "should have policies defined" do
      assignment_model
      @a.broadcast_policy_list.should_not be_empty
    end
    
    
    context "due date changed" do
      it "should have an 'Assignment Due Date Changed' policy" do
        assignment_model
        @a.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Assignment Due Date Changed')
      end
      
      it "should create a message when an assignment due date has changed" do
        Notification.create(:name => 'Assignment Due Date Changed')
        assignment_model(:title => 'Assignment with unstable due date')
        @a.context.offer!
        @a.created_at = 1.month.ago
        @a.due_at = Time.now + 60
        @a.save!
        @a.messages_sent.should be_include('Assignment Due Date Changed')
      end
      
      it "should NOT create a message when everything but the assignment due date has changed" do
        Notification.create(:name => 'Assignment Due Date Changed')
        t = Time.parse("Sep 1, 2009 5:00pm")
        assignment_model(:title => 'Assignment with unstable due date', :due_at => t)
        @a.due_at.should eql(t)
        @a.context.offer!
        @a.submission_types = "online_url"
        @a.title = "New Title"
        @a.due_at = t + 1
        @a.description = "New description"
        @a.points_possible = 50
        @a.save!
        @a.messages_sent.should_not be_include('Assignment Due Date Changed')
      end
    end
    
    context "assignment graded" do
      it "should notify students when their grade is changed" do
        setup_unpublished_assignment_with_students
        @assignment.publish!
        @assignment.should be_published
        @sub2 = @assignment.grade_student(@stu2, :grade => 8).first
        @sub2.messages_sent.should_not be_empty
        @sub2.messages_sent['Submission Graded'].should_not be_nil
        @sub2.messages_sent['Submission Grade Changed'].should be_nil
        @sub2.update_attributes(:graded_at => Time.now - 60*60)
        @sub2 = @assignment.grade_student(@stu2, :grade => 9).first
        @sub2.messages_sent.should_not be_empty
        @sub2.messages_sent['Submission Graded'].should be_nil
        @sub2.messages_sent['Submission Grade Changed'].should_not be_nil
      end
      it "should not notify students of grade changes if unpublished" do
        setup_unpublished_assignment_with_students
        @assignment.publish!
        @assignment.should be_published
        @assignment.unpublish!
        @assignment.should be_available
        @sub2 = @assignment.grade_student(@stu2, :grade => 8).first
        @sub2.messages_sent.should be_empty
        @sub2.update_attributes(:graded_at => Time.now - 60*60)
        @sub2 = @assignment.grade_student(@stu2, :grade => 9).first
        @sub2.messages_sent.should be_empty
      end
      it "should notify affected students on a mass-grade change" do
        setup_unpublished_assignment_with_students
        @assignment.publish!
        @assignment.set_default_grade(:default_grade => 10)
        @assignment.messages_sent.should_not be_nil
        @assignment.messages_sent['Assignment Graded'].should_not be_nil
      end
      
      it "should notify affected students of a grade change when the assignment is republished" do
        setup_unpublished_assignment_with_students
        @assignment.publish!
        @assignment.should be_published
        @assignment.unpublish!
        @assignment.should be_available
        @sub2 = @assignment.grade_student(@stu2, :grade => 8).first
        @sub2.messages_sent.should be_empty
        @sub2.update_attributes(:graded_at => Time.now - 60*60)
        @assignment.reload
        @assignment.publish!
        @subs = @assignment.updated_submissions
        @subs.should_not be_nil
        @subs.should_not be_empty
        @sub = @subs.detect{|s| s.user_id == @stu2.id }
        @sub.messages_sent.should_not be_nil
        @sub.messages_sent['Submission Grade Changed'].should_not be_nil
        @sub = @subs.detect{|s| s.user_id != @stu2.id }
        @sub.messages_sent.should_not be_nil
        @sub.messages_sent['Submission Grade Changed'].should be_nil
      end
      
      it "should not notify unaffected students of a grade change when the assignment is republished" do
        setup_unpublished_assignment_with_students
        @assignment.publish!
        @assignment.should be_published
        @assignment.unpublish!
        @assignment.should be_available
        @assignment.publish!
        @subs = @assignment.updated_submissions
        @subs.should_not be_nil
        @sub = @subs.first
        @sub.messages_sent.should_not be_nil
        @sub.messages_sent['Submission Grade Changed'].should be_nil
      end

      it "should include re-submitted submissions in the list of submissions needing grading" do
        setup_unpublished_assignment_with_students
        @enr1.accept!
        @assignment.publish!
        @assignment.should be_published
        @assignment.submissions.size.should == 1
        Assignment.need_grading_info(15, []).find_by_id(@assignment.id).should be_nil
        @assignment.submit_homework(@stu1, :body => "Changed my mind!")
        @sub1.reload
        @sub1.body.should == "Changed my mind!"
        Assignment.need_grading_info(15, []).find_by_id(@assignment.id).should_not be_nil
      end
    end
    
    context "assignment changed" do
      it "should have an 'Assignment Changed' policy" do
        assignment_model
        @a.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Assignment Changed')
      end
      
      it "should create a message when an assigment changes after it's been published" do
        Notification.create(:name => 'Assignment Changed')
        assignment_model
        @a.context.offer!
        @a.created_at = Time.parse("Jan 2 2000")
        @a.description = "something different"
        @a.notify_of_update = true
        @a.save
        @a.messages_sent.should be_include('Assignment Changed')
      end
      
      it "should NOT create a message when an assigment changes SHORTLY AFTER it's been created" do
        Notification.create(:name => 'Assignment Changed')
        assignment_model
        @a.context.offer!
        @a.description = "something different"
        @a.save
        @a.messages_sent.should_not be_include('Assignment Changed')
      end
      
      # it "should NOT create a message when the content changes to an empty string" do
        # Notification.create(:name => 'Assignment Changed')
        # assignment_model(:name => 'Assignment with unstable due date')
        # @a.context.offer!
        # @a.description = ""
        # @a.created_at = Date.new
        # @a.save!
        # @a.messages_sent.should_not be_include('Assignment Changed')
      # end
    end
    
    context "assignment created" do
      it "should have an 'Assignment Created' policy" do
        assignment_model
        @a.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Assignment Created')
      end
      
      # it "should create a message when an assigment is added to a course in process" do
      #   Notification.create(:name => 'Assignment Created')
      #   @course = Course.create
      #   @course.offer
      #   assignment_model(:context => @course)
      #   require 'rubygems'
      #   require 'ruby-debug'
      #   debugger
      #   @a.messages_sent.should be_include('Assignment Created')
      # end
    end
    
    context "assignment graded" do
      it "should have an 'Assignment Graded' policy" do
        assignment_model
        @a.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Assignment Graded')
      end
      
      it "should create a message when an assignment is published" do
        setup_assignment
        Notification.create(:name => 'Assignment Graded')
        @user = User.create
        assignment_model
        @a.unpublish!
        @a.context.offer!
        @c.enroll_student(@user)
#        @students = [@user]
#        @a.stub!(:participants).and_return(@students)
#        @a.participants.should be_include(@user)
        @a.previously_published = false
        @a.save
        @a.publish!
        @a.messages_sent.should be_include('Assignment Graded')
      end
    end
    
    
  end
  context "group assignment" do
    it "should submit the homework for all students in the same group" do
      setup_assignment_with_group
      sub = @a.submit_homework(@u1, :submission_type => "online_text_entry", :body => "Some text for you")
      sub.user_id.should eql(@u1.id)
      @a.reload
      subs = @a.submissions
      subs.length.should eql(2)
      subs.map(&:group_id).uniq.should eql([@group.id])
      subs.map(&:submission_type).uniq.should eql(['online_text_entry'])
      subs.map(&:body).uniq.should eql(['Some text for you'])
    end
    
    it "should update submission for all students in the same group" do
      setup_assignment_with_group
      res = @a.grade_student(@u1, :grade => "10")
      res.should_not be_nil
      res.should_not be_empty
      res.length.should eql(2)
      res.map{|s| s.user}.should be_include(@u1)
      res.map{|s| s.user}.should be_include(@u2)
    end
    
    it "should add a submission comment for only the specified user by default" do
      setup_assignment_with_group
      res = @a.grade_student(@u1, :comment => "woot")
      res.should_not be_nil
      res.should_not be_empty
      res.length.should eql(1)
      res.find{|s| s.user == @u1}.submission_comments.should_not be_empty
      res.find{|s| s.user == @u2}.should be_nil #.submission_comments.should be_empty
    end
    it "should update submission for only the individual student if set thay way" do
      setup_assignment_with_group
      @a.grade_group_students_individually = true
      @a.save!
      res = @a.grade_student(@u1, :grade => "10")
      res.should_not be_nil
      res.should_not be_empty
      res.length.should eql(1)
      res[0].user.should eql(@u1)
    end
    it "should add a submission comment for all group members if specified" do
      setup_assignment_with_group
      res = @a.grade_student(@u1, :comment => "woot", :group_comment => "1")
      res.should_not be_nil
      res.should_not be_empty
      res.length.should eql(2)
      res.find{|s| s.user == @u1}.submission_comments.should_not be_empty
      res.find{|s| s.user == @u2}.submission_comments.should_not be_empty
    end
    it "return the single submission if the user is not in a group" do
      setup_assignment_with_group
      res = @a.grade_student(@u3, :comment => "woot", :group_comment => "1")
      res.should_not be_nil
      res.should_not be_empty
      res.length.should eql(1)
      res.find{|s| s.user == @u3}.submission_comments.should_not be_empty
    end
  end
    
  context "adheres_to_policy" do
    it "should return the same grants_right? with nil parameters" do
      course_with_teacher(:active_all => true)
      @assignment = @course.assignments.create!(:title => "some assignment")
      rights = @assignment.grants_rights?(@user)
      rights.should_not be_empty
      rights.should == @assignment.grants_rights?(@user, nil)
      rights.should == @assignment.grants_rights?(@user, nil, nil)
    end
    
    it "should serialize permissions" do
      course_with_teacher(:active_all => true)
      @assignment = @course.assignments.create!(:title => "some assignment")
      data = ActiveSupport::JSON.decode(@assignment.to_json(:permissions => {:user => @user, :session => nil})) rescue nil
      data.should_not be_nil
      data['assignment'].should_not be_nil
      data['assignment']['permissions'].should_not be_nil
      data['assignment']['permissions'].should_not be_empty
    end
  end
  
  context "assignment reminders" do
    it "should generate reminders" do
      course_with_student
      d = Time.now
      @assignment = @course.assignments.create!(:title => "some assignment", :due_at => d + 1.week, :submission_types => "online_url")
      @assignment.generate_reminders!
      @assignment.assignment_reminders.should_not be_nil
      @assignment.assignment_reminders.length.should eql(1)
      @assignment.assignment_reminders[0].user_id.should eql(@user.id)
      @assignment.assignment_reminders[0].remind_at.should eql(@assignment.due_at - @user.reminder_time_for_due_dates)
    end
  end
  
  context "clone_for" do
    it "should clone for another course" do
      course_with_teacher
      @assignment = @course.assignments.create!(:title => "some assignment")
      course
      @new_assignment = @assignment.clone_for(@course)
      @new_assignment.context.should_not eql(@assignment.context)
      @new_assignment.title.should eql(@assignment.title)
    end
  end
end

def setup_assignment_with_group
  assignment_model(:group_category => "Study Groups")
  @group = @a.context.groups.create!(:name => "Study Group 1", :category => "Study Groups")
  @u1 = @a.context.enroll_user(User.create(:name => "user 1")).user
  @u2 = @a.context.enroll_user(User.create(:name => "user 2")).user
  @u3 = @a.context.enroll_user(User.create(:name => "user 3")).user
  @group.add_user(@u1)
  @group.add_user(@u2)
end
def setup_assignment_without_submission
  # Established course too, as a context
  assignment_model
  user_model
  e = @course.enroll_student(@user)
  e.invite
  e.accept
end

def setup_assignment_with_homework
  setup_assignment_without_submission
  res = @assignment.submit_homework(@user, {:submission_type => 'online_text_entry'})
  res.should_not be_nil
  res.should be_is_a(Submission)
  @assignment.reload
end

def setup_unpublished_assignment_with_students
  Notification.create!(:name => "Assignment Graded")
  Notification.create!(:name => "Submission Graded")
  Notification.create!(:name => "Submission Grade Changed")
  course_model(:publish_grades_immediately => false)
  @course.offer!
  @enr1 = @course.enroll_student(@stu1 = user)
  @enr2 = @course.enroll_student(@stu2 = user)
  @assignment = @course.assignments.create(:title => "asdf", :points_possible => 10)
  @assignment.should_not be_published
  @sub1 = @assignment.grade_student(@stu1, :grade => 9).first
  @sub1.score.should == 9
  # Took this out until it is asked for
  # @sub1.published_score.should_not == @sub1.score
  @sub1.published_score.should == @sub1.score
  @assignment.reload
  @assignment.submissions.should be_include(@sub1)
end

def setup_assignment
  @u = factory_with_protected_attributes(User, :name => "some user", :workflow_state => "registered")
  @c = course_model(:workflow_state => "available")
  @c.enroll_student(@u)
end
