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

describe SubmissionsApiController, :type => :integration do

  def submit_homework(assignment, student, opts = {:body => "test!"})
    @submit_homework_time ||= 0
    @submit_homework_time += 1.hour
    sub = assignment.find_or_create_submission(student)
    if sub.versions.size == 1
      Version.update_all({:created_at => Time.at(@submit_homework_time)}, {:id => sub.versions.first.id})
    end
    sub.workflow_state = 'submitted'
    yield(sub) if block_given?
    update_with_protected_attributes!(sub, { :submitted_at => Time.at(@submit_homework_time), :created_at => Time.at(@submit_homework_time) }.merge(opts))
    sub.versions(true).each { |v| Version.update_all({ :created_at => v.model.created_at }, { :id => v.id }) }
    sub
  end

  it "should 404 if there is no submission" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    @assignment = @course.assignments.create!(:title => 'assignment1', :grading_type => 'points', :points_possible => 12)
    raw_api_call(:get,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'show',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :include => %w(submission_history submission_comments rubric_assessment) })
    response.status.should match /404/
  end

  it "should return student discussion entries for discussion_topic assignments" do
    @student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(@student).accept!
    @context = @course
    @assignment = factory_with_protected_attributes(@course.assignments, {:title => 'assignment1', :submission_types => 'discussion_topic', :discussion_topic => discussion_topic_model})

    e1 = @topic.discussion_entries.create!(:message => 'main entry', :user => @user)
    se1 = @topic.discussion_entries.create!(:message => 'sub 1', :user => @student, :parent_entry => e1)
    @assignment.submit_homework(@student, :submission_type => 'discussion_topic')
    se2 = @topic.discussion_entries.create!(:message => 'student 1', :user => @student)
    @assignment.submit_homework(@student, :submission_type => 'discussion_topic')
    e1 = @topic.discussion_entries.create!(:message => 'another entry', :user => @user)

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{@student.id}.json",
          { :controller => 'submissions_api', :action => 'show',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => @student.id.to_s })

    json['discussion_entries'].should ==
      [{
        'message' => 'sub 1',
        'user_id' => @student.id,
        'created_at' => se1.created_at.as_json,
        'updated_at' => se1.updated_at.as_json,
      },
      {
        'message' => 'student 1',
        'user_id' => @student.id,
        'created_at' => se2.created_at.as_json,
        'updated_at' => se2.updated_at.as_json,
      }]
  end

  it "should return a valid preview url for quiz submissions" do
    student1 = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student1).accept!
    quiz = Quiz.create!(:title => 'quiz1', :context => @course)
    quiz.did_edit!
    quiz.offer!
    a1 = quiz.assignment
    sub = a1.find_or_create_submission(student1)
    sub.submission_type = 'online_quiz'
    sub.workflow_state = 'submitted'
    sub.save!

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions.json",
          { :controller => 'submissions_api', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s },
          { :include => %w(submission_history submission_comments rubric_assessment) })

    get_via_redirect json.first['preview_url']
    response.should be_success
    response.body.should match(/Redirecting to quiz page/)
  end

  it "should return all submissions for an assignment" do
    student1 = user(:active_all => true)
    student2 = user(:active_all => true)

    course_with_teacher_logged_in(:active_all => true)

    @course.enroll_student(student1).accept!
    @course.enroll_student(student2).accept!

    a1 = @course.assignments.create!(:title => 'assignment1', :grading_type => 'letter_grade', :points_possible => 15)
    rubric = rubric_model(:user => @user, :context => @course,
                          :data => larger_rubric_data)
    a1.create_rubric_association(:rubric => rubric, :purpose => 'grading', :use_for_grading => true)

    submit_homework(a1, student1)
    submit_homework(a1, student1, :media_comment_id => "54321", :media_comment_type => "video")
    sub1 = submit_homework(a1, student1) { |s| s.attachments = [attachment_model(:context => student1, :folder => nil)] }

    sub2 = submit_homework(a1, student2, :url => "http://www.instructure.com") { |s| s.attachment = attachment_model(:context => s, :filename => 'snapshot.png', :content_type => 'image/png') }

    a1.grade_student(student1, {:grade => '90%', :comment => "Well here's the thing...", :media_comment_id => "3232", :media_comment_type => "audio"})
    sub1.reload
    sub1.submission_comments.size.should == 1
    comment = sub1.submission_comments.first
    ra = a1.rubric_association.assess(
          :assessor => @user, :user => student2, :artifact => sub2,
          :assessment => {:assessment_type => 'grading', :criterion_crit1 => { :points => 7 }, :criterion_crit2 => { :points => 2, :comments => 'Hmm'}})

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions.json",
          { :controller => 'submissions_api', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s },
          { :include => %w(submission_history submission_comments rubric_assessment) })

    res =
      [{"grade"=>"A-",
        "prior"=>nil,
        "body"=>"test!",
        "assignment_id" => a1.id,
        "submitted_at"=>"1970-01-01T03:00:00Z",
        "preview_url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student1.id}?preview=1",
        "grade_matches_current_submission"=>true,
        "attachments" =>
         [
           { "content-type" => "application/loser",
             "url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student1.id}?download=#{sub1.attachments.first.id}",
             "filename" => "unknown.loser",
             "display_name" => "unknown.loser" },
         ],
        "submission_history"=>
         [{"grade"=>nil,
           "prior"=>nil,
           "body"=>"test!",
           "assignment_id" => a1.id,
           "submitted_at"=>"1970-01-01T01:00:00Z",
           "attempt"=>1,
           "url"=>nil,
           "focus"=>nil,
           "submission_type"=>"online_text_entry",
           "user_id"=>student1.id,
           "comparison"=>nil,
           "preview_url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student1.id}?preview=1&version=0",
           "grade_matches_current_submission"=>nil,
           "score"=>nil},
          {"grade"=>nil,
            "assignment_id" => a1.id,
           "media_comment" =>
            { "content-type" => "video/mp4",
              "url" => "http://www.example.com/courses/#{@course.id}/media_download?entryId=54321&redirect=1&type=mp4" },
           "prior"=>nil,
           "body"=>"test!",
           "submitted_at"=>"1970-01-01T02:00:00Z",
           "attempt"=>2,
           "url"=>nil,
           "focus"=>nil,
           "submission_type"=>"online_text_entry",
           "user_id"=>student1.id,
           "comparison"=>nil,
           "preview_url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student1.id}?preview=1&version=1",
           "grade_matches_current_submission"=>nil,
           "score"=>nil},
          {"grade"=>"A-",
            "assignment_id" => a1.id,
           "media_comment" =>
            { "content-type" => "video/mp4",
              "url" => "http://www.example.com/courses/#{@course.id}/media_download?entryId=54321&redirect=1&type=mp4" },
           "attachments" =>
            [
              { "content-type" => "application/loser",
                "url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student1.id}?download=#{sub1.attachments.first.id}",
                "filename" => "unknown.loser",
                "display_name" => "unknown.loser" },
            ],
           "prior"=>nil,
           "body"=>"test!",
           "submitted_at"=>"1970-01-01T03:00:00Z",
           "attempt"=>3,
           "url"=>nil,
           "focus"=>nil,
           "submission_type"=>"online_text_entry",
           "user_id"=>student1.id,
           "comparison"=>nil,
           "preview_url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student1.id}?preview=1&version=2",
           "grade_matches_current_submission"=>true,
           "score"=>13.5}],
        "attempt"=>3,
        "url"=>nil,
        "focus"=>nil,
        "submission_type"=>"online_text_entry",
        "user_id"=>student1.id,
        "submission_comments"=>
         [{"comment"=>"Well here's the thing...",
           "media_comment" => {
             "content-type" => "audio/mp4",
             "url" => "http://www.example.com/courses/#{@course.id}/media_download?entryId=3232&redirect=1&type=mp4",
           },
           "created_at"=>comment.created_at.as_json,
           "author_name"=>"User",
           "author_id"=>student1.id}],
        "comparison"=>nil,
        "media_comment" =>
         { "content-type" => "video/mp4",
           "url" => "http://www.example.com/courses/#{@course.id}/media_download?entryId=54321&redirect=1&type=mp4" },
        "score"=>13.5},
       {"grade"=>"F",
        "assignment_id" => a1.id,
        "prior"=>nil,
        "body"=>nil,
        "preview_url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student2.id}?preview=1",
        "grade_matches_current_submission"=>true,
        "submitted_at"=>"1970-01-01T04:00:00Z",
        "submission_history"=>
         [{"grade"=>"F",
           "assignment_id" => a1.id,
           "prior"=>nil,
           "body"=>nil,
           "submitted_at"=>"1970-01-01T04:00:00Z",
           "attempt"=>1,
           "url"=>"http://www.instructure.com",
           "focus"=>nil,
           "submission_type"=>"online_url",
           "user_id"=>student2.id,
           "comparison"=>nil,
           "preview_url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student2.id}?preview=1&version=0",
          "grade_matches_current_submission"=>true,
           "attachments" =>
            [{"content-type" => "image/png",
              "display_name" => "snapshot.png",
              "filename" => "snapshot.png",
              "url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student2.id}?download=#{sub2.attachment.id}",}],
           "score"=>9}],
        "attempt"=>1,
        "url"=>"http://www.instructure.com",
        "focus"=>nil,
        "submission_type"=>"online_url",
        "user_id"=>student2.id,
        "attachments" =>
         [{"content-type" => "image/png",
           "display_name" => "snapshot.png",
           "filename" => "snapshot.png",
           "url" => "http://www.example.com/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student2.id}?download=#{sub2.attachment.id}",}],
        "submission_comments"=>[],
        "comparison"=>nil,
        "score"=>9,
        "rubric_assessment"=>
         {"crit2"=>{"comments"=>"Hmm", "points"=>2},
          "crit1"=>{"comments"=>nil, "points"=>7}}}]
    json.should == res
  end

  it "should return all submissions for a student" do
    student1 = user(:active_all => true)
    student2 = user(:active_all => true)

    course_with_teacher_logged_in(:active_all => true)

    @course.enroll_student(student1).accept!
    @course.enroll_student(student2).accept!

    a1 = @course.assignments.create!(:title => 'assignment1', :grading_type => 'letter_grade', :points_possible => 15)
    a2 = @course.assignments.create!(:title => 'assignment2', :grading_type => 'letter_grade', :points_possible => 25)

    submit_homework(a1, student1)
    submit_homework(a2, student1)
    submit_homework(a1, student2)

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/students/submissions.json",
          { :controller => 'submissions_api', :action => 'for_students',
            :format => 'json', :course_id => @course.to_param },
          { :student_ids => [student1.to_param] })

    json.size.should == 2
    json.all? { |submission| submission['user_id'].should == student1.id }.should be_true

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/students/submissions.json",
          { :controller => 'submissions_api', :action => 'for_students',
            :format => 'json', :course_id => @course.to_param },
          { :student_ids => [student1.to_param, student2.to_param] })

    json.size.should == 3

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/students/submissions.json",
          { :controller => 'submissions_api', :action => 'for_students',
            :format => 'json', :course_id => @course.to_param },
          { :student_ids => [student1.to_param, student2.to_param],
            :assignment_ids => [a1.to_param] })

    json.size.should == 2
    json.all? { |submission| submission['assignment_id'].should == a1.id }.should be_true
  end

  it "should allow grading an uncreated submission" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    a1 = @course.assignments.create!(:title => 'assignment1', :grading_type => 'letter_grade', :points_possible => 15)

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s, :id => student.id.to_s },
          { :submission => { :posted_grade => 'B' } })

    Submission.count.should == 1
    @submission = Submission.first

    json['grade'].should == 'B'
    json['score'].should == 12.9
  end

  it "should not return submissions for no-longer-enrolled students" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    enrollment = @course.enroll_student(student)
    enrollment.accept!
    assignment = @course.assignments.create!(:title => 'assignment1', :grading_type => 'letter_grade', :points_possible => 15)
    submit_homework(assignment, student)

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignments/#{assignment.id}/submissions.json",
          { :controller => 'submissions_api', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => assignment.id.to_s })
    json.length.should == 1

    enrollment.destroy

    json = api_call(:get,
          "/api/v1/courses/#{@course.id}/assignments/#{assignment.id}/submissions.json",
          { :controller => 'submissions_api', :action => 'index',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => assignment.id.to_s })
    json.length.should == 0
  end

  it "should allow updating the grade for an existing submission" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    a1 = @course.assignments.create!(:title => 'assignment1', :grading_type => 'letter_grade', :points_possible => 15)
    submission = a1.find_or_create_submission(student)
    submission.should_not be_new_record
    submission.grade = 'A'
    submission.save!

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s, :id => student.id.to_s },
          { :submission => { :posted_grade => 'B' } })

    Submission.count.should == 1
    @submission = Submission.first
    submission.id.should == @submission.id

    json['grade'].should == 'B'
    json['score'].should == 12.9
  end

  it "should allow submitting points" do
    submit_with_grade({ :grading_type => 'points', :points_possible => 15 }, '13.2', 13.2, '13.2')
  end

  it "should allow submitting points above points_possible (for extra credit)" do
    submit_with_grade({ :grading_type => 'points', :points_possible => 15 }, '16', 16, '16')
  end

  it "should allow submitting percent to a points assignment" do
    submit_with_grade({ :grading_type => 'points', :points_possible => 15 }, '50%', 7.5, '7.5')
  end

  it "should allow submitting percent" do
    submit_with_grade({ :grading_type => 'percent', :points_possible => 10 }, '75%', 7.5, "75%")
  end

  it "should allow submitting points to a percent assignment" do
    submit_with_grade({ :grading_type => 'percent', :points_possible => 10 }, '5', 5, "50%")
  end

  it "should allow submitting percent above points_possible (for extra credit)" do
    submit_with_grade({ :grading_type => 'percent', :points_possible => 10 }, '105%', 10.5, "105%")
  end

  it "should allow submitting letter_grade as a letter score" do
    submit_with_grade({ :grading_type => 'letter_grade', :points_possible => 15 }, 'B', 12.9, 'B')
  end

  it "should allow submitting letter_grade as a numeric score" do
    submit_with_grade({ :grading_type => 'letter_grade', :points_possible => 15 }, '11.9', 11.9, 'B-')
  end

  it "should allow submitting letter_grade as a percentage score" do
    submit_with_grade({ :grading_type => 'letter_grade', :points_possible => 15 }, '70%', 10.5, 'C-')
  end

  it "should reject letter grades sent to a points assignment" do
    submit_with_grade({ :grading_type => 'points', :points_possible => 15 }, 'B-', nil, nil)
  end

  it "should allow submitting pass_fail (pass)" do
    submit_with_grade({ :grading_type => 'pass_fail', :points_possible => 12 }, 'pass', 12, "complete")
  end

  it "should allow submitting pass_fail (fail)" do
    submit_with_grade({ :grading_type => 'pass_fail', :points_possible => 12 }, 'fail', 0, "incomplete")
  end

  it "should allow a points score for pass_fail, at full points" do
    submit_with_grade({ :grading_type => 'pass_fail', :points_possible => 12 }, '12', 12, "complete")
  end

  it "should allow a points score for pass_fail, at zero points" do
    submit_with_grade({ :grading_type => 'pass_fail', :points_possible => 12 }, '0', 0, "incomplete")
  end

  it "should allow a percentage score for pass_fail, at full points" do
    submit_with_grade({ :grading_type => 'pass_fail', :points_possible => 12 }, '100%', 12, "complete")
  end

  it "should reject any other type of score for a pass_fail assignment" do
    submit_with_grade({ :grading_type => 'pass_fail', :points_possible => 12 }, '50%', nil, nil)
  end

  def submit_with_grade(assignment_opts, param, score, grade)
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    a1 = @course.assignments.create!({:title => 'assignment1'}.merge(assignment_opts))

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s, :id => student.id.to_s },
          { :submission => { :posted_grade => param } })

    Submission.count.should == 1
    @submission = Submission.first

    json['score'].should == score
    json['grade'].should == grade
  end

  it "should allow posting a rubric assessment" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    a1 = @course.assignments.create!(:title => 'assignment1', :grading_type => 'points', :points_possible => 12)
    rubric = rubric_model(:user => @user, :context => @course,
                          :data => larger_rubric_data)
    a1.create_rubric_association(:rubric => rubric, :purpose => 'grading', :use_for_grading => true)

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s, :id => student.id.to_s },
          { :rubric_assessment =>
             { :crit1 => { :points => 7 },
               :crit2 => { :points => 2, :comments => 'Rock on' } } })

    Submission.count.should == 1
    @submission = Submission.first
    @submission.user_id.should == student.id
    @submission.score.should == 9
    @submission.rubric_assessment.should_not be_nil
    @submission.rubric_assessment.data.should ==
      [{:description=>"B",
        :criterion_id=>"crit1",
        :comments_enabled=>true,
        :points=>7,
        :learning_outcome_id=>nil,
        :id=>"rat2",
        :comments=>nil},
      {:description=>"Pass",
        :criterion_id=>"crit2",
        :comments_enabled=>true,
        :points=>2,
        :learning_outcome_id=>nil,
        :id=>"rat1",
        :comments=>"Rock on"}]
  end

  it "should allow posting a comment on a submission" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    @assignment = @course.assignments.create!(:title => 'assignment1', :grading_type => 'points', :points_possible => 12)
    submit_homework(@assignment, student)

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :comment =>
            { :text_comment => "ohai!" } })

    Submission.count.should == 1
    @submission = Submission.first
    json['submission_comments'].size.should == 1
    json['submission_comments'].first['comment'].should == 'ohai!'
  end

  it "should allow posting a media comment on a submission, given a kaltura id" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    @assignment = @course.assignments.create!(:title => 'assignment1', :grading_type => 'points', :points_possible => 12)

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :comment =>
            { :media_comment_id => '1234', :media_comment_type => 'audio' } })

    Submission.count.should == 1
    @submission = Submission.first
    json['submission_comments'].size.should == 1
    comment = json['submission_comments'].first
    comment['comment'].should == 'This is a media comment.'
    comment['media_comment']['url'].should == "http://www.example.com/courses/#{@course.id}/media_download?entryId=1234&redirect=1&type=mp4"
    comment['media_comment']["content-type"].should == "audio/mp4"
  end

  it "should allow commenting on an uncreated submission" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    a1 = @course.assignments.create!(:title => 'assignment1', :grading_type => 'letter_grade', :points_possible => 15)

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{a1.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => a1.id.to_s, :id => student.id.to_s },
          { :comment => { :text_comment => "Why U no submit" } })

    Submission.count.should == 1
    @submission = Submission.first

    comment = @submission.submission_comments.first
    comment.should be_present
    comment.comment.should == "Why U no submit"
  end

  it "should allow clearing out the current grade with a blank grade" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    @assignment = @course.assignments.create!(:title => 'assignment1', :grading_type => 'points', :points_possible => 12)
    @assignment.grade_student(student, { :grade => '10' })
    Submission.count.should == 1
    @submission = Submission.first
    @submission.grade.should == '10'
    @submission.score.should == 10
    @submission.workflow_state.should == 'graded'

    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :submission => { :posted_grade => '' } })
    Submission.count.should == 1
    @submission = Submission.first
    @submission.grade.should be_nil
    @submission.score.should be_nil
  end

  it "should allow repeated changes to a submission to accumulate" do
    student = user(:active_all => true)
    course_with_teacher_logged_in(:active_all => true)
    @course.enroll_student(student).accept!
    @assignment = @course.assignments.create!(:title => 'assignment1', :grading_type => 'points', :points_possible => 12)
    submit_homework(@assignment, student)

    # post a comment
    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :comment => { :text_comment => "This works" } })
    Submission.count.should == 1
    @submission = Submission.first

    # grade the submission
    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :submission => { :posted_grade => '10' } })
    Submission.count.should == 1
    @submission = Submission.first

    # post another comment
    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :comment => { :text_comment => "10/12 ain't bad" } })
    Submission.count.should == 1
    @submission = Submission.first

    json['grade'].should == '10'
    @submission.grade.should == '10'
    @submission.score.should == 10
    json['body'].should == 'test!'
    @submission.body.should == 'test!'
    json['submission_comments'].size.should == 2
    json['submission_comments'].first['comment'].should == "This works"
    json['submission_comments'].last['comment'].should == "10/12 ain't bad"
    @submission.user_id.should == student.id

    # post another grade
    json = api_call(:put,
          "/api/v1/courses/#{@course.id}/assignments/#{@assignment.id}/submissions/#{student.id}.json",
          { :controller => 'submissions_api', :action => 'update',
            :format => 'json', :course_id => @course.id.to_s,
            :assignment_id => @assignment.id.to_s, :id => student.id.to_s },
          { :submission => { :posted_grade => '12' } })
    Submission.count.should == 1
    @submission = Submission.first

    json['grade'].should == '12'
    @submission.grade.should == '12'
    @submission.score.should == 12
    json['body'].should == 'test!'
    @submission.body.should == 'test!'
    json['submission_comments'].size.should == 2
    json['submission_comments'].first['comment'].should == "This works"
    json['submission_comments'].last['comment'].should == "10/12 ain't bad"
    @submission.user_id.should == student.id
  end

end
