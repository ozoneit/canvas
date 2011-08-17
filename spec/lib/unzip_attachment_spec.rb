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

describe UnzipAttachment do
  
  before do
    course_model
    folder_model(:name => 'course files')
    @course.folders << @folder
    @course.save!
    @course.reload
    @filename = File.expand_path(File.join(File.dirname(__FILE__), %w(.. fixtures attachments.zip)))
    @ua = UnzipAttachment.new(:course => @course, :filename => @filename)
  end
  
  it "should store a course, course_files_folder, and filename" do
    @ua.course.should eql(@course)
    @ua.filename.should eql(@filename)
    @ua.course_files_folder.should eql(@folder)
  end

  it "should be able to take a root_folder argument" do
    folder_model(:name => "a special folder")
    @course.folders << @folder
    @course.save!
    @course.reload
    ua = UnzipAttachment.new(:course => @course, :filename => @filename, :root_directory => @folder)
    ua.course_files_folder.should eql(@folder)
    
    ua = UnzipAttachment.new(:course => @course, :filename => @filename, :root_directory => @folder)
    ua.course_files_folder.should eql(@folder)
    
  end
  
  it "should unzip the file, create folders, and stick the contents of the zipped file as attachments in the folders" do
    @ua.process

    @course.reload
    @course.attachments.find_by_display_name('first_entry.txt').should_not be_nil
    @course.attachments.find_by_display_name('first_entry.txt').folder.name.should eql('course files')

    @course.folders.find_by_full_name('course files/adir').should_not be_nil
    @course.attachments.find_by_display_name('second_entry.txt').should_not be_nil
    @course.attachments.find_by_display_name('second_entry.txt').folder.full_name.should eql('course files/adir')

  end
  
  it "should be able to overwrite files in a folder on the database" do
    # Not overwriting FileInContext.attach, so we're actually attaching the files now.
    # The identical @us.process guarantees that every file attached the second time 
    # overwrites a file that was already there.
    @ua.process
    lambda{@ua.process}.should_not raise_error
    @course.reload
    @course.attachments.find_all_by_display_name('first_entry.txt').size.should eql(2)
    @course.attachments.find_all_by_display_name('first_entry.txt').any?{|a| a.file_state == 'deleted' }.should eql(true) #first.file_state.should eql('deleted')
    @course.attachments.find_all_by_display_name('first_entry.txt').any?{|a| a.file_state == 'available' }.should eql(true) #last.file_state.should eql('available')
    @course.attachments.find_all_by_display_name('second_entry.txt').size.should eql(2)
    @course.attachments.find_all_by_display_name('second_entry.txt').any?{|a| a.file_state == 'deleted' }.should eql(true) #first.file_state.should eql('deleted')
    @course.attachments.find_all_by_display_name('second_entry.txt').any?{|a| a.file_state == 'available' }.should eql(true) #last.file_state.should eql('available')
  end
end

class G
  @@list = []
  def self.<<(val)
    @@list << val
  end
  
  def self.list
    @@list
  end
end
