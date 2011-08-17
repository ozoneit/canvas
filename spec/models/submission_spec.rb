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

describe Submission do
  before(:each) do
    @user = factory_with_protected_attributes(User, :name => "some student", :workflow_state => "registered")
    # @user = mock_model(User)
    # @user.stub!(:id).and_return(1)
    @context = factory_with_protected_attributes(Course, :name => "some course", :workflow_state => "available")
    @context.enroll_student(@user)
    # @context = mock("context")
    # @context.stub!(:students).and_return([@user])
    @assignment = @context.assignments.new(:title => "some assignment")
    @assignment.workflow_state = "published"
    @assignment.save
    # @assignment = mock_model(Assignment)
    # @assignment.stub!(:context).and_return(@context)
    @valid_attributes = {
      :assignment_id => @assignment.id,
      :user_id => @user.id,
      :grade => "1.5",
      :url => "www.instructure.com"
    }
  end

  it "should create a new instance given valid attributes" do
    Submission.create!(@valid_attributes)
  end
  
  it "should offer the context, if one is available" do
    @course = mock_model(Course)
    @assignment = mock_model(Assignment)
    @assignment.should_receive(:context).and_return(@course)
    
    @submission = Submission.new
    lambda{@submission.context}.should_not raise_error
    @submission.context.should be_nil
    @submission.assignment = @assignment
    @submission.context.should eql(@course)
  end
  
  it "should have an interesting state machine" do
    submission_spec_model
    @submission.state.should eql(:submitted)
    @submission.grade_it
    @submission.state.should eql(:graded)
  end
  
  it "should be versioned" do
    submission_spec_model
    @submission.should be_respond_to(:versions)
  end

  context "broadcast policy" do
    it "should have a broadcast policy" do
      submission_spec_model
      @submission.should be_respond_to(:dispatch)
      @submission.should be_respond_to(:to)
    end
    
    it "should have 6 policies defined" do
      submission_spec_model
      @submission.broadcast_policy_list.size.should eql(6)
    end
        
    context "Assignment Submitted Late" do
      it "should have a 'Assignment Submitted Late' policy" do
        submission_spec_model
        @submission.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Assignment Submitted Late')
      end
      
      it "should create a message when the assignment is turned in late" do
        Notification.create(:name => 'Assignment Submitted Late')
        t = User.create(:name => "some teacher")
        s = User.create(:name => "late student")
        @context.enroll_teacher(t)
        @context.enroll_student(s)
#        @context.stub!(:teachers).and_return([@user])
        @assignment.workflow_state = "published"
        @assignment.update_attributes(:due_at => Time.now - 1000)
#        @assignment.stub!(:due_at).and_return(Time.now - 100)
        submission_spec_model(:user => s)
        
#        @submission.stub!(:validate_enrollment).and_return(true)
#        @submission.save
        @submission.messages_sent.should be_include('Assignment Submitted Late')
      end
    end
    
    context "Submission Graded" do
      it "should have a 'Submission Graded' policy" do
        submission_spec_model
        @submission.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Submission Graded')
      end
      
      it "should create a message when the assignment has been graded and published" do
        Notification.create(:name => 'Submission Graded')
        submission_spec_model
        @cc = @user.communication_channels.create(:path => "somewhere")
        @submission.reload
        @submission.assignment.should eql(@assignment)
        @submission.assignment.state.should eql(:published)
#        @assignment.stub!(:state).and_return(:published)
#        @cc = mock_model(CommunicationChannel)
#        @cc.stub!(:path).and_return('somewhere@example.com')
#        @cc.stub!(:user).and_return(@user)
#        @user.stub!(:communication_channel).and_return(@cc)
#        @submission.stub!(:student).and_return(@user)
        @submission.grade_it!
        @submission.messages_sent.should be_include('Submission Graded')
      end
    end
    
    context "Submission Grade Changed" do
      it "should have a 'Submission Grade Changed' policy" do
        submission_spec_model
        @submission.broadcast_policy_list.map {|bp| bp.dispatch}.should be_include('Submission Grade Changed')
      end
      
      it "should create a message when the score is changed and the grades were already published" do
        Notification.create(:name => 'Submission Grade Changed')
        @assignment.stub!(:score_to_grade).and_return(10.0)
        @assignment.stub!(:due_at).and_return(Time.now  - 100)
        submission_spec_model

        @cc = @user.communication_channels.create(:path => "somewhere")
        s = @assignment.grade_student(@user, :grade => 10)[0] #@submission
        s.graded_at = Time.parse("Jan 1 2000")
        s.save
        @submission = @assignment.grade_student(@user, :grade => 9)[0]
        @submission.should eql(s)
        @submission.messages_sent.should be_include('Submission Grade Changed')
      end
      
      it "should create a message when the score is changed and the grades were already published" do
        Notification.create(:name => 'Submission Grade Changed')
        Notification.create(:name => 'Submission Graded')
        @assignment.stub!(:score_to_grade).and_return(10.0)
        @assignment.stub!(:due_at).and_return(Time.now  - 100)
        submission_spec_model

        @cc = @user.communication_channels.create(:path => "somewhere")
        s = @assignment.grade_student(@user, :grade => 10)[0] #@submission
        @submission = @assignment.grade_student(@user, :grade => 9)[0]
        @submission.should eql(s)
        @submission.messages_sent.should_not be_include('Submission Grade Changed')
        @submission.messages_sent.should be_include('Submission Graded')
      end
      
      it "should NOT create a message when the score is changed and the submission was recently graded" do
        Notification.create(:name => 'Submission Grade Changed')
        @assignment.stub!(:score_to_grade).and_return(10.0)
        @assignment.stub!(:due_at).and_return(Time.now  - 100)
        submission_spec_model

        @cc = @user.communication_channels.create(:path => "somewhere")
        s = @assignment.grade_student(@user, :grade => 10)[0] #@submission
        @submission = @assignment.grade_student(@user, :grade => 9)[0]
        @submission.should eql(s)
        @submission.messages_sent.should_not be_include('Submission Grade Changed')
      end
    end
  end

  context "URL submissions" do
    it "should automatically add the 'http://' scheme if none given" do
      s = Submission.create!(@valid_attributes)
      s.url.should == 'http://www.instructure.com'

      long_url = ("a"*300 + ".com")
      s.url = long_url
      s.save!
      s.url.should == "http://#{long_url}"
      # make sure it adds the "http://" to the body for long urls, too
      s.body.should == "http://#{long_url}"
    end

    it "should reject invalid urls" do
      s = Submission.create(@valid_attributes.merge :url => 'bad url')
      s.new_record?.should be_true
      s.errors.length.should == 1
      s.errors.first.to_s.should match(/not a valid URL/)
    end
  end
  
end

def submission_spec_model(opts={})
  @submission = Submission.new(@valid_attributes.merge(opts))
  @submission.assignment.should eql(@assignment)
  @assignment.context.should eql(@context)
  @submission.assignment.context.should eql(@context)
  @submission.save
end
