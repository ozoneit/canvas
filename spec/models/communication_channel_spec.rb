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

describe CommunicationChannel do
  before(:each) do
    @pseudonym = mock_model(Pseudonym)
    @pseudonym.stub!(:destroyed?).and_return(false)
    Pseudonym.stub!(:find_by_user_id).and_return(@pseudonym)
  end

  it "should create a new instance given valid attributes" do
    factory_with_protected_attributes(CommunicationChannel, communication_channel_valid_attributes)
  end
  
  context "find_all_for" do
    it "should find all *active* matching channels based on a user's notification policies" do
      user_model(:workflow_state => 'registered')
      a = communication_channel_model(:user_id => @user.id, :workflow_state => 'active')
      b = communication_channel_model(:user_id => @user.id, :workflow_state => 'active', :path => "path2@example.com")
      c = communication_channel_model(:user_id => @user.id, :workflow_state => 'active', :path => "path3@example.com")
      d = communication_channel_model(:user_id => @user.id, :path => "path4@example.com")
      notification_model
      notification_policy_model(:communication_channel_id => a.id, :notification_id => @notification.id, :user_id => @user.id )
      notification_policy_model(:communication_channel_id => b.id, :notification_id => @notification.id, :user_id => @user.id )
      notification_policy_model(:communication_channel_id => c.id, :notification_id => @notification.id, :user_id => @user.id )
      @user.reload
      channels = CommunicationChannel.find_all_for(@user, @notification)
      channels.should include(a)
      channels.should include(b)
      channels.should include(c)
      channels.should_not include(d)
    end
    
    it "should find the default channel if a user has notification policies but none match" do
      @u = user_model(:workflow_state => 'registered')
      a = communication_channel_model(:user_id => @u.id, :workflow_state => 'active')
      b = communication_channel_model(:user_id => @u.id, :path => "path2@example.com")
      c = communication_channel_model(:user_id => @u.id, :path => "path3@example.com")
      a.should be_active
      a.should 

      @n = Notification.create(:name => "New Notification")
      @u.notification_policies.create(:communication_channel => a, :notification => @n)
      channels = CommunicationChannel.find_all_for(@u, @n)
      channels.should eql([@u.communication_channel])
    end
    
    it "should find a default channel if no policies are specified" do
      @u = user_model(:workflow_state => 'registered')
      a = @u.communication_channels.create(:path => "a@example.com")
      a.confirm!
      b = @u.communication_channels.create(:path => "b@example.com")
      c = @u.communication_channels.create(:path => "c@example.com")
      @n = Notification.create(:name => "New Notification", :category => 'TestImmediately')
      @u.reload
      channels = CommunicationChannel.find_all_for(@u, @n)
      channels.should include(a)
      channels.should_not include(b)
      channels.should_not include(c)
    end
    
    it "should consider notification_policies" do
      @user = user_model(:workflow_state => 'registered')
      a = @user.communication_channels.create(:path => "a@example.com")
      a.confirm!
      b = @user.communication_channels.create(:path => "b@example.com")
      b.confirm!
      @n = Notification.create!(:name => "New notification", :category => 'TestImmediately')
      @user.reload
      channels = CommunicationChannel.find_all_for(@user, @n)
      channels.should include(a)
      channels.should_not include(b)
      
      @user.notification_policies.create!(:communication_channel => b, :notification => @n, :frequency => 'immediately')
      channels = CommunicationChannel.find_all_for(@user, @n)
      channels.should include(b)
      channels.should_not include(a)
    end
    
    it "should not return channels for 'daily' or 'weekly' policies" do
      @user = user_model(:workflow_state => 'registered')
      a = @user.communication_channels.create(:path => "a@example.com")
      a.confirm!
      @n = Notification.create!(:name => "New notification")
      @user.notification_policies.create!(:communication_channel => a, :notification => @n, :frequency => 'daily')
      channels = CommunicationChannel.find_all_for(@user, @n)
      channels.should be_empty
    end
    
    it "should find only the specified channel (whether or not it's active) for registration notifications" do
      @u = User.create(:name => "user")
      a = @u.communication_channels.create(:path => "a@example.com")
      b = @u.communication_channels.create(:path => "b@example.com")
      c = @u.communication_channels.create(:path => "c@example.com")
      @n = Notification.create(:name => "New Notification", :category => "Registration")
      channels = CommunicationChannel.find_all_for(@u, @n, c)
      channels.should_not include(a)
      channels.should_not include(b)
      channels.should include(c)
    end
    
    it "should find only the specified channel (whether or not it's active) for registration notifications" do
      @u = User.create(:name => "user")
      a = @u.communication_channels.create(:path => "a@example.com")
      b = @u.communication_channels.create(:path => "b@example.com")
      c = @u.communication_channels.create(:path => "c@example.com")
      @n = Notification.create(:name => "New Notification", :category => "Registration")
      channels = CommunicationChannel.find_all_for(@u, @n, c)
      channels.should_not include(a)
      channels.should_not include(b)
      channels.should include(c)
    end
  end
  
  it "should have a decent state machine" do
    communication_channel_model
    @cc.state.should eql(:unconfirmed)
    @cc.confirm
    @cc.state.should eql(:active)
    @cc.retire
    @cc.state.should eql(:retired)
    @cc.re_activate
    @cc.state.should eql(:active)
    
    communication_channel_model(:path => "another_path@example.com")
    @cc.state.should eql(:unconfirmed)
    @cc.retire
    @cc.state.should eql(:retired)
    @cc.re_activate
    @cc.state.should eql(:active)
  end
  
  it "should reset the bounce count when re_activating" do
    communication_channel_model
    @cc.bounce_count = 1
    @cc.confirm
    @cc.bounce_count.should eql(1)
    @cc.retire
    @cc.re_activate
    @cc.bounce_count.should eql(0)
  end
  
  it "should retire the communication channel if it's been bounced 5 times" do
    communication_channel_model
    @cc.bounce_count = 5
    @cc.state.should eql(:unconfirmed)
    @cc.save
    @cc.state.should eql(:retired)
    
    communication_channel_model
    @cc.bounce_count = 4
    @cc.save
    @cc.state.should eql(:unconfirmed)

    communication_channel_model
    @cc.bounce_count = 6
    @cc.save
    @cc.state.should eql(:retired)
  end
  
  it "should set a confirmation code unless one has been set" do
    AutoHandle.should_receive(:generate).at_least(:once).and_return('abc123')
    communication_channel_model
    @cc.confirmation_code.should eql('abc123')
  end
  
  it "should be able to reset a confirmation code" do
    communication_channel_model
    old_cc = @cc.confirmation_code
    @cc.set_confirmation_code(true)
    @cc.confirmation_code.should_not eql(old_cc)
  end
  
  it "should use a 15-digit confirmation code for default or email path_type settings" do
    communication_channel_model
    @cc.path_type.should eql('email')
    @cc.confirmation_code.size.should eql(25)
  end
  
  it "should use a 4-digit confirmation_code for settings other than email" do
    communication_channel_model
    @cc.path_type = 'sms'
    @cc.set_confirmation_code(true)
    @cc.confirmation_code.size.should eql(4)
  end
  
  it "should default the path type to email" do
    communication_channel_model
    @cc.path_type.should eql('email')
  end
  
  it "should only allow email, sms, or chat as path types" do
    communication_channel_model
    @cc.path_type = 'email'; @cc.save
    @cc.path_type.should eql('email')

    @cc.path_type = 'sms'; @cc.save
    @cc.path_type.should eql('sms')

    @cc.path_type = 'chat'; @cc.save
    @cc.path_type.should eql('chat')

    @cc.path_type = 'not valid'; @cc.save
    @cc.path_type.should eql('email')
  end
  
  it "should act as list" do
    CommunicationChannel.should be_respond_to(:acts_as_list)
  end
  
  it "should scope the list to the user" do
    @u1 = User.create!
    @u2 = User.create!
    @u1.should_not eql(@u2)
    @u1.id.should_not eql(@u2.id)
    @cc1 = factory_with_protected_attributes(CommunicationChannel, communication_channel_valid_attributes.merge(:user => @u1))
    @cc2 = factory_with_protected_attributes(CommunicationChannel, communication_channel_valid_attributes.merge(:user => @u1))
    @cc3 = factory_with_protected_attributes(CommunicationChannel, communication_channel_valid_attributes.merge(:user => @u2))
    @cc1.user.should eql(@u1)
    @cc2.user.should eql(@u1)
    @cc3.user.should eql(@u2)
    @cc1.user_id.should_not eql(@cc3.user_id)
    @cc2.position.should eql(2)
    @cc2.move_to_top
    @cc2.save
    @cc2.reload
    @cc2.position.should eql(1)
    @cc1.reload
    @cc1.position.should eql(2)
    @cc3.reload
    @cc3.position.should eql(1)
  end
  
  it "should have a proper type formatted for the screen" do
    communication_channel_model
    @cc.proper_type.should eql("Email Address")
    @cc.path_type = 'sms'
    @cc.proper_type.should eql("Cell Number")
    @cc.path_type = 'chat'
    @cc.proper_type.should eql("Chat")
    @cc.path_type= 'not valid'
    @cc.proper_type.should eql("Email Address")
  end
  
  context "can_notify?" do
    it "should normally be able to be used" do
      communication_channel_model
      @communication_channel.should be_can_notify
    end
    
    it "should not be able to be used if it has a policy to not use it" do
      communication_channel_model
      notification_policy_model(:frequency => "never", :communication_channel_id => @communication_channel.id)
      @communication_channel.reload
      @communication_channel.should_not be_can_notify
    end
  end
  
end
