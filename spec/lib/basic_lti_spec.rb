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

describe BasicLTI do
  describe "generate_params" do
    it "should generate a correct signature" do
      BasicLTI.explicit_signature_settings('1251600739', 'c8350c0e47782d16d2fa48b2090c1d8f')
      res = BasicLTI.generate_params({
        :resource_link_id                   => '120988f929-274612',
        :user_id                            => '292832126',
        :roles                              => 'Instructor',
        :lis_person_name_full               => 'Jane Q. Public',
        :lis_person_contact_email_primary   => 'user@school.edu',
        :lis_person_sourced_id              => 'school.edu:user',
        :context_id                         => '456434513',
        :context_title                      => 'Design of Personal Environments',
        :context_label                      => 'SI182',
        :lti_version                        => 'LTI-1p0',
        :lti_message_type                   => 'basic-lti-launch-request',
        :tool_consumer_instance_guid        => 'lmsng.school.edu',
        :tool_consumer_instance_description => 'University of School (LMSng)',
        :basiclti_submit                    => 'Launch Endpoint with BasicLTI Data'
      }, 'http://dr-chuck.com/ims/php-simple/tool.php', '12345', 'secret')
      res['oauth_signature'].should eql('TPFPK4u3NwmtLt0nDMP1G1zG30U=')
    end
  end
  
  describe "generate" do
    it "should generate correct parameters" do
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.create!(:domain => 'yahoo.com', :consumer_key => '12345', :shared_secret => 'secret', :name => 'tool')
      hash = BasicLTI.generate('http://www.yahoo.com', @tool, @user, @course, '123456', 'http://www.google.com')
      hash['lti_message_type'].should == 'basic-lti-launch-request'
      hash['lti_version'].should == 'LTI-1p0'
      hash['resource_link_id'].should == '123456'
      hash['resource_link_title'].should == @tool.name
      hash['user_id'].should == @user.opaque_identifier(:asset_string)
      hash['roles'].should == 'Instructor'
      hash['context_id'].should == @course.opaque_identifier(:asset_string)
      hash['context_title'].should == @course.name
      hash['context_label'].should == @course.course_code
      hash['launch_presentation_local'].should == 'en-US'
      hash['launch_presentation_document_target'].should == 'iframe'
      hash['launch_presentation_width'].should == '600'
      hash['launch_presentation_height'].should == '400'
      hash['launch_presentation_return_url'].should == 'http://www.google.com'
      hash['tool_consumer_instance_guid'].should == "#{@course.root_account.opaque_identifier(:asset_string)}.#{HostUrl.context_host(@course)}"
      hash['tool_consumer_instance_name'].should == @course.root_account.name
      hash['tool_consumer_instance_contact_email'].should == HostUrl.outgoing_email_address
      hash['oauth_callback'].should == 'about:blank'
    end
    
    it "should include custom fields" do
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.create!(:domain => 'yahoo.com', :consumer_key => '12345', :shared_secret => 'secret', :custom_fields => {'custom_bob' => 'bob', 'custom_fred' => 'fred', 'john' => 'john'}, :name => 'tool')
      hash = BasicLTI.generate('http://www.yahoo.com', @tool, @user, @course, '123456', 'http://www.yahoo.com')
      hash['custom_bob'].should eql('bob')
      hash['custom_fred'].should eql('fred')
      hash['john'].should be_nil
    end
    
    it "should not include name and email if anonymous" do
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.create!(:domain => 'yahoo.com', :consumer_key => '12345', :shared_secret => 'secret', :privacy_level => 'anonymous', :name => 'tool')
      @tool.include_name?.should eql(false)
      @tool.include_email?.should eql(false)
      hash = BasicLTI.generate('http://www.yahoo.com', @tool, @user, @course, '123456', 'http://www.yahoo.com')
      hash['lis_person_name_given'].should be_nil
      hash['lis_person_name_family'].should be_nil
      hash['lis_person_name_full'].should be_nil
      hash['lis_person_contact_email_primary'].should be_nil
    end
    
    it "should include name if name_only" do
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.create!(:domain => 'yahoo.com', :consumer_key => '12345', :shared_secret => 'secret', :privacy_level => 'name_only', :name => 'tool')
      @tool.include_name?.should eql(true)
      @tool.include_email?.should eql(false)
      hash = BasicLTI.generate('http://www.yahoo.com', @tool, @user, @course, '123456', 'http://www.yahoo.com')
      hash['lis_person_name_given'].should == nil
      hash['lis_person_name_family'].should == 'User'
      hash['lis_person_name_full'].should == @user.name
      hash['lis_person_contact_email_primary'].should be_nil
    end
    
    it "should include email if public" do
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.create!(:domain => 'yahoo.com', :consumer_key => '12345', :shared_secret => 'secret', :privacy_level => 'public', :name => 'tool')
      @tool.include_name?.should eql(true)
      @tool.include_email?.should eql(true)
      hash = BasicLTI.generate('http://www.yahoo.com', @tool, @user, @course, '123456', 'http://www.yahoo.com')
      hash['lis_person_name_given'].should == nil
      hash['lis_person_name_family'].should == 'User'
      hash['lis_person_name_full'].should == @user.name
      hash['lis_person_contact_email_primary'] = @user.email
    end
  end
end
