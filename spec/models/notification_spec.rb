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

describe Notification do

  it "should create a new instance given valid attributes" do
    Notification.create!(notification_valid_attributes)
  end
  
  it "should have a default delay_for" do
    notification_model
    @notification.delay_for.should be >= 0
  end
  
  it "should have a decent state machine" do
    notification_model
    @notification.state.should eql(:active)
    @notification.deactivate
    @notification.state.should eql(:inactive)
    @notification.reactivate
    @notification.state.should eql(:active)
  end
  
  it "should always have some subject and body" do
    n = Notification.create
    n.body.should_not be_nil
    n.subject.should_not be_nil
    n.sms_body.should_not be_nil
  end
  
  context "create_message" do
    it "should only send dashboard messages for users with non-validated channels" do
      notification_model
      u1 = create_user_with_cc(:name => "user 1", :workflow_state => "registered")
      u1.communication_channels.create(:path => "user1@example.com")
      u2 = create_user_with_cc(:name => "user 2")
      u2.communication_channels.create(:path => "user2@example.com")
      @a = Assignment.create
      messages = @notification.create_message(@a, u1, u2)
      messages.length.should eql(2)
      messages.map(&:to).should be_include('dashboard')
    end
    
    it "should not send dispatch messages for pre-registered users" do
      notification_model
      u1 = user_model(:name => "user 2")
      u1.communication_channels.create(:path => "user2@example.com").confirm!
      @a = Assignment.create
      messages = @notification.create_message(@a, u1)
      messages.should be_empty
    end
    
    it "should send registration messages for pre-registered users" do
      notification_set(:user_opts => {:workflow_state => "pre_registered"}, :notification_opts => {:category => "Registration"})
      messages = @notification.create_message(@assignment, @user)
      messages.should_not be_empty
      messages.length.should eql(1)
      messages.first.to.should eql(@communication_channel.path)
    end
    
    it "should send dashboard and dispatch messages for registered users based on default policies" do
      notification_model(:category => 'TestImmediately')
      u1 = user_model(:name => "user 1", :workflow_state => "registered")
      u1.communication_channels.create(:path => "user1@example.com").confirm!
      @a = Assignment.create
      messages = @notification.create_message(@a, u1)
      messages.should_not be_empty
      messages.length.should eql(2)
      messages[0].to.should eql("user1@example.com")
      messages[1].to.should eql("dashboard")
    end
    
    it "should not dispatch non-immediate message based on default policies" do
      notification_model(:category => 'TestDaily',:name => "Show In Feed")
      @notification.default_frequency.should eql("daily")
      u1 = user_model(:name => "user 1", :workflow_state => "registered")
      u1.communication_channels.create(:path => "user1@example.com").confirm!
      @a = Assignment.create
      messages = @notification.create_message(@a, u1)
      messages.should_not be_empty
      messages.length.should eql(1)
      messages[0].to.should eql("dashboard")
      DelayedMessage.all.should_not be_empty
      DelayedMessage.last.should_not be_nil
      DelayedMessage.last.notification_id.should eql(@notification.id)
      DelayedMessage.last.communication_channel_id.should eql(u1.communication_channel.id)
      DelayedMessage.last.send_at.should > Time.now.utc
    end
    
    it "should send dashboard (but not dispatch messages) for registered users based on default policies" do
      notification_model(:category => 'TestNever', :name => "Show In Feed")
      @notification.default_frequency.should eql("never")
      u1 = user_model(:name => "user 1", :workflow_state => "registered")
      u1.communication_channels.create(:path => "user1@example.com").confirm!
      @a = Assignment.create
      messages = @notification.create_message(@a, u1)
      messages.should_not be_empty
      messages.length.should eql(1)
      messages[0].to.should eql("dashboard")
    end

    it "should replace messages when a similar notification occurs" do
      notification_set
      
      all_messages = []
      messages = @notification.create_message(@assignment, @user)
      all_messages += messages
      messages.length.should eql(2)
      m1 = messages.first
      m2 = messages.last
      
      messages = @notification.create_message(@assignment, @user)
      all_messages += messages
      messages.should_not be_empty
      messages.length.should eql(2)
      
      all_messages.select {|m| 
        m.to == m1.to and m.notification == m1.notification and m.communication_channel == m1.communication_channel
      }.length.should eql(2)

      all_messages.select {|m| 
        m.to == m2.to and m.notification == m2.notification and m.communication_channel == m2.communication_channel
      }.length.should eql(2)
    end
    
    it "should replace dashboard messages when a similar notification occurs" do
      notification_set(:notification_opts => {:name => "Show In Feed"})
      
      messages = @notification.create_message(@assignment, @user)
      messages.length.should eql(2)
      messages.select{|m| m.to == "dashboard"}.length.should eql(1)
      StreamItem.for_user(@user).count.should eql(1)
      
      messages = @notification.create_message(@assignment, @user)
      messages.length.should eql(2)
      StreamItem.for_user(@user).count.should eql(2)
    end
    
    it "should create stream items" do
      notification_set(:notification_opts => {:name => "Show In Feed"})
      StreamItem.for_user(@user).count.should eql(0)
      messages = @notification.create_message(@assignment, @user)
      StreamItem.for_user(@user).count.should eql(1)
      si = StreamItem.for_user(@user).first
      si.item_asset_string.should eql("message_")
    end
    
    it "should translate ERB in the notification" do
      notification_set
      messages = @notification.create_message(@assignment, @user)
      messages.each {|m| m.subject.should eql("This is 5!")}
    end
    
    it "should not get confused with nil values in the to list" do
      notification_set
      messages = @notification.create_message(@assignment, nil)
      messages.should be_empty
    end
    
    it "should not send messages after the user's limit" do
      notification_set
      Rails.cache.delete(['recent_messages_for', @user.id].cache_key)
      User.stub!(:max_messages_per_day).and_return(1)
      User.max_messages_per_day.times do 
        messages = @notification.create_message(@assignment, @user)
        messages.select{|m| m.to != 'dashboard'}.should_not be_empty
      end
      DelayedMessage.count.should eql(0)
      messages = @notification.create_message(@assignment, @user)
      messages.select{|m| m.to != 'dashboard'}.should be_empty
      DelayedMessage.count.should eql(1)
    end
    
    it "should not send messages after the category limit" do
      notification_set
      Rails.cache.delete(['recent_messages_for', "#{@user.id}_#{@notification.category}"].cache_key)
      @notification.stub!(:max_for_category).and_return(1)
      @notification.max_for_category.times do
        messages = @notification.create_message(@assignment, @user)
        messages.select{|m| m.to != 'dashboard'}.should_not be_empty
      end
      DelayedMessage.count.should eql(0)
      messages = @notification.create_message(@assignment, @user)
      messages.select{|m| m.to != 'dashboard'}.should be_empty
      DelayedMessage.count.should eql(1)
    end
    
  end
  
  context "record_delayed_messages" do
    before do
      user_model
      communication_channel_model(:user_id => @user.id)
      @cc.confirm
      notification_model
      # Universal context
      assignment_model
      @valid_record_delayed_messages_opts = {
        :user => @user,
        :communication_channel => @cc,
        :asset => @assignment
      }
    end
    
    it "should only work when a user is passed to it" do
      lambda{@notification.record_delayed_messages}.should raise_error(ArgumentError, "Must provide a user")
    end
    
    it "should only work when a communication_channel is passed to it" do
      # One without a communication_channel, gets cc explicitly through 
      # :to => cc or implicitly through the user. 
      user_model 
      lambda{@notification.record_delayed_messages(:user => @user)}.should raise_error(ArgumentError, 
        "Must provide an asset")
    end
    
    it "should only work when a context is passed to it" do
      lambda{@notification.record_delayed_messages(:user => @user, :to => @communication_channel)}.should raise_error(ArgumentError, 
        "Must provide an asset")
    end
    
    it "should work with a user, communication_channel, and context" do
      lambda{@notification.record_delayed_messages(@valid_record_delayed_messages_opts)}.should_not raise_error
    end
    
    context "testing that the applicable daily or weekly policies exist" do
      before do
        NotificationPolicy.delete_all

        @trifecta_opts = {
          :user_id => @user.id, 
          :communication_channel_id => @communication_channel.id, 
          :notification_id => @notification.id
        }
      end
        
      it "should return false without these policies in place" do
        notification_policy_model
        @notification.record_delayed_messages(@valid_record_delayed_messages_opts).should be_false
      end
      
      it "should return false with the right models and the wrong policies" do
        notification_policy_model({:frequency => "immediately"}.merge(@trifecta_opts) )
        @notification.record_delayed_messages(@valid_record_delayed_messages_opts).should be_false
        
        notification_policy_model({:frequency => "never"}.merge(@trifecta_opts) )
        @notification.record_delayed_messages(@valid_record_delayed_messages_opts).should be_false
      end
      
      it "should return the delayed message model with the right models and the daily policies" do
        notification_policy_model({:frequency => "daily"}.merge(@trifecta_opts) )
        @user.reload
        delayed_messages = @notification.record_delayed_messages(@valid_record_delayed_messages_opts)
        delayed_messages.should be_is_a(Array)
        delayed_messages.size.should eql(1)
        delayed_messages.each {|x| x.should be_is_a(DelayedMessage) }
      end

      it "should return the delayed message model with the right models and the weekly policies" do
        notification_policy_model({:frequency => "weekly"}.merge(@trifecta_opts) )
        @user.reload
        delayed_messages = @notification.record_delayed_messages(@valid_record_delayed_messages_opts)
        delayed_messages.should be_is_a(Array)
        delayed_messages.size.should eql(1)
        delayed_messages.each {|x| x.should be_is_a(DelayedMessage) }
      end
      
      it "should return the delayed message model with the right models and a mix of policies" do
        notification_policy_model({:frequency => "immediately"}.merge(@trifecta_opts) )
        notification_policy_model({:frequency => "never"}.merge(@trifecta_opts) )
        notification_policy_model({:frequency => "daily"}.merge(@trifecta_opts) )
        notification_policy_model({:frequency => "weekly"}.merge(@trifecta_opts) )
        @user.reload
        delayed_messages = @notification.record_delayed_messages(@valid_record_delayed_messages_opts)
        delayed_messages.should be_is_a(Array)
        delayed_messages.size.should eql(2)
        delayed_messages.each {|x| x.should be_is_a(DelayedMessage) }
      end
      
      it "should actually create the DelayedMessage model" do
        i = DelayedMessage.all.size
        notification_policy_model({:frequency => "weekly"}.merge(@trifecta_opts) )
        @user.reload
        @notification.record_delayed_messages(@valid_record_delayed_messages_opts)
        DelayedMessage.all.size.should eql(i + 1)
      end
      
      it "should do things" do
        true
      end
        
    end # testing that the applicable daily or weekly policies exist
  end # delay message
end


def notification_set(opts={})
  user_opts = opts.delete(:user_opts) || {}
  notification_opts = opts.delete(:notification_opts)  || {}
  
  assignment_model
  notification_model({:subject => "This is <%= '5' %>!", :name => "Test Name"}.merge(notification_opts))
  user_model({:workflow_state => 'registered'}.merge(user_opts))
  communication_channel_model(:user_id => @user).confirm!
  notification_policy_model(
    :notification_id => @notification.id, 
    :user_id => @user.id,
    :communication_channel_id => @communication_channel.id
  )
  @notification.reload
end

# The opts pertain to user only
def create_user_with_cc(opts={})
  if @notification
    notification_policy_model(:notification_id => @notification.id)
    communication_channel_model
    @communication_channel.notification_policies << @notification_policy
  else
    communication_channel_model
  end
  
  user_model(opts)
  @communication_channel.update_attribute(:user_id, @user.id)
  @user.reload
  @user
end
