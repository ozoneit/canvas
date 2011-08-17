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

module Turnitin
  class Client
    
    attr_accessor :endpoint, :account_id, :shared_secret, :testing
    def initialize(account_id, shared_secret, testing=false)
      @host = "api.turnitin.com"
      @endpoint = "/api.asp"
      raise "Account ID required" unless account_id
      raise "Shared secret required" unless shared_secret
      @account_id = account_id
      @shared_secret = shared_secret
      @testing = testing
      @functions = {
        :create_user              => '1', # instructor or student
        :create_course             => '2', # instructor only
        :enroll_student           => '3', # student only
        :create_assignment        => '4', # instructor only
        :submit_paper             => '5', # student or teacher
        :generate_report          => '6',
        :show_paper               => '7',
        :delete_paper             => '8',
        :change_password          => '9',
        :list_papers              => '10',
        :check_user_paper         => '11',
        :view_admin_statistics    => '12',
        :view_grade_mark          => '13',
        :report_turnaround_times  => '14',
        :submission_scores        => '15',
        :login_user               => '17',
        :logout_user              => '18',
      }
    end
    
    def id(obj)
      if @testing
        "test_#{obj.asset_string}"
      else
        "#{account_id}_#{obj.asset_string}"
      end
    end
    
    def email(item)
      # emails @example.com are, guaranteed by RFCs, to be like /dev/null :)
      null_email = "#{item.asset_string}@null.instructure.example.com"
      if item.is_a?(User)
        item.email || null_email
      else
        null_email
      end
    end
    
    def testSettings
      user = OpenObject.new({
        :asset_string => "admin_test",
        :first_name => "Admin",
        :last_name => "Test",
        :name => "Admin Test"
      })
      res = createTeacher(user)
      !!res
    end
    
    def createStudent(user)
      res = sendRequest(:create_user, 2, :user => user, :utp => '1')
      res.css("userid")[0].content rescue nil
    end
    
    def createTeacher(user)
      res = sendRequest(:create_user, 2, :user => user, :utp => '2')
      res.css("userid")[0].content rescue nil
    end
    
    def createCourse(course)
      res = sendRequest(:create_course, 2, :utp => '2', :course => course, :user => course, :utp => '2')
      res.css("classid")[0].content rescue nil
    end
    
    def enrollStudent(course, student)
      res = sendRequest(:enroll_student, 2, :user => student, :course => course, :utp => '1', :tem => email(course))
      res.css("userid")[0].content rescue nil
    end
    
    def createAssignment(assignment)
      course = assignment.context
      today = ActiveSupport::TimeWithZone.new(Time.now, Time.zone).to_date
      # s_paper_check       - 1/0, check student paper repository (is this the CURRENT student's repo, or all other students on the same paper???)
      # internet_check      - 1/0, check internet repo
      # journal_check       - 1/0, check journals, periodicals, publications
      # institution_check   - 1/0, check institution
      # submit_papers_to    - 0=none, 1=standard, 2=institution
      # exclude_biblio      - 1/0, exclude bibliographic material
      # exclude_quoted      - 1/0, exclude quoted material
      # exclude_type        - 0=none, 1=by_word_count, 2=by_percentage
      # exclude_value       - goes with exclude_type, either num or pct based on type
      res = sendRequest(:create_assignment, '2',
        :user => course,
        :course => course,
        :assignment => assignment,
        :utp => '2', 
        :dtstart => "#{today.strftime} 00:00:00", 
        :dtdue => "#{today.strftime} 00:00:00", 
        :dtpost => "#{today.strftime} 00:00:00", 
        :s_view_report => "1", 
        :late_accept_flag => '1',
        :post => true
      )
      res.css("assignmentid")[0].content rescue nil
    end
    
    def submitPaper(submission)
      student = submission.user
      assignment = submission.assignment
      course = assignment.context
      submission.turnitin_data ||= {}
      object_ids = []
      if submission.submission_type == 'online_upload'
        attachments = submission.attachments.select{|a| a.turnitinable? }
        data = StringIO.new()
        attachments.each do |a|
          res = nil
          Tempfile.open(a.display_name) do |tempfile|
            file = File.open(tempfile.path, 'wb')
            AWS::S3::S3Object.stream(a.full_filename, a.bucket_name) do |chunk|
             file.write chunk
            end
            file.close
            file = File.open(tempfile.path, 'rb')
            res = sendRequest(:submit_paper, '2', :post => true, :utp => '1', :ptl => a.display_name, :pdata => file, :ptype => "2", :user => student, :course => course, :assignment => assignment, :tem => email(course))
            file.close
          end
          object_id = res.css("objectID")[0].content rescue nil
          if object_id
            submission.turnitin_data[a.asset_string] = {:object_id => object_id}
            submission.turnitin_data_changed!
            submission.send_at(5.minutes.from_now, :check_turnitin_status, a.asset_string)
            object_ids << object_id
          end
        end
      elsif submission.submission_type == 'online_text_entry'
        res = sendRequest(:submit_paper, '2', :post => true, :utp => '1', :ptl => assignment.title, :pdata => submission.plaintext_body, :ptype => "1", :user => student, :course => course, :assignment => assignment, :tem => email(course))
        object_id = res.css("objectID")[0].content rescue nil
        if object_id
          submission.turnitin_data[submission.asset_string] = {:object_id => object_id}
          submission.turnitin_data_changed!
          submission.send_at(5.minutes.from_now, :check_turnitin_status, submission.asset_string)
          object_ids << object_id
        end
      else
        raise "Unsupported submission type for turnitin integration: #{submission.submission_type}"
      end
      submission.save
      object_ids
    end
    
    def generateReport(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data[asset_string][:object_id] rescue nil
      res = nil
      res = sendRequest(:generate_report, 2, :oid => object_id, :utp => '2', :user => course, :course => course, :assignment => assignment) if object_id
      data = {}
      if res
        data[:similarity_score] = res.css("originalityscore")[0].content rescue nil
        data[:web_overlap] = res.css("web_overlap")[0].content rescue nil
        data[:publication_overlap] = res.css("publication_overlap")[0].content rescue nil
        data[:student_overlap] = res.css("student_paper_overlap")[0].content rescue nil
      end
      data
    end
    
    def submissionReportUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data[asset_string][:object_id] rescue nil
      sendRequest(:generate_report, 1, :oid => object_id, :utp => '2', :user => course, :course => course, :assignment => assignment)
    end
    
    def submissionStudentReportUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data[asset_string][:object_id] rescue nil
      sendRequest(:generate_report, 1, :oid => object_id, :utp => '1', :user => user, :course => course, :assignment => assignment, :tem => email(course))
    end
    
    def submissionPreviewUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data[asset_string][:object_id] rescue nil
      sendRequest(:show_paper, 1, :oid => object_id, :utp => '1', :user => user, :course => course, :assignment => assignment, :tem => email(course))
    end
    
    def submissionDownloadUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data[asset_string][:object_id] rescue nil
      sendRequest(:show_paper, 1, :oid => object_id, :utp => '1', :user => user, :course => course, :assignment => assignment, :tem => email(course))
    end
    
    def listSubmissions(assignment)
      course = assignment.context
      sendRequest(:list_papers, 2, :assignment => assignment, :course => course, :user => course, :utp => '1', :tem => email(course))
    end
    
    def request_md5(params)
      keys_used = []
      str = ""
      keys = [:aid,:assign,:assignid,:cid,:cpw,:ctl,:diagnostic,:dis,:dtdue,:dtstart,:dtpost,:encrypt,:fcmd,:fid,:gmtime,:newassign,:newupw,:oid,:pfn,:pln,:ptl,:ptype,:said,:tem,:uem,:ufn,:uid,:uln,:upw,:utp]
      keys.each do |key|
        keys_used << key if params[key] && !params[key].empty?
        str += (params[key] || "")
      end
      str += @shared_secret
      Digest::MD5.hexdigest(str)
    end
    
    def sendRequest(command, fcmd, args)
      user = args.delete :user
      course = args.delete :course
      assignment = args.delete :assignment
      post = args.delete :post
      params = args.merge({
        :gmtime => Time.now.utc.strftime("%Y%m%d%H%M")[0,11],
        :fid => @functions[command],
        :fcmd => fcmd.to_s,
        :encrypt => '0',
        :aid => @account_id,
        :src => '15',
        :dis => '1'
      })
      if user
        params[:uid] = id(user)
        params[:uem] = email(user)
        if user.is_a?(Course)
          params[:ufn] = user.name
          params[:uln] = "Course"
        else
          params[:ufn] = user.name
          params[:uln] = "Student"
        end
      end
      if course
        params[:cid] = id(course)
        params[:ctl] = course.name
      end
      if assignment
        params[:assign] = assignment.title
        params[:assignid] = id(assignment)
      end
      params[:diagnostic] = "1" if @testing
      
      md5 = request_md5(params)
      require 'net/http'
      
      if post
        params[:md5] = md5
        mp = Multipart::MultipartPost.new
        query, headers = mp.prepare_query(params)
        puts query if @testing
        http = Net::HTTP.new(@host, 443)
        http.use_ssl = true
        res = http.start{|con|
          req = Net::HTTP::Post.new(@endpoint, headers)
          con.read_timeout = 30
          begin
            res = con.request(req, query)
          rescue => e
            Rails.logger.error("Turnitin API error for account_id #{@account_id}: POSTING FAILED")
            Rails.logger.error(params.to_json)
          end
        }
      else
        requestParams = "md5=#{md5}"
        params.each do |key, value|
          next if value.nil?
          requestParams += "&#{URI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
        end
        puts requestParams if @testing
        if params[:fcmd] == '1'
          return "https://#{@host}#{@endpoint}?#{requestParams}"
        else
          http = Net::HTTP.new(@host, 443)
          http.use_ssl = true
          res = http.start{|conn| 
            conn.get("#{@endpoint}?#{requestParams}")
          }
        end
      end
      if @testing
        puts res.body
        nil
      else
        doc = Nokogiri(res.body) rescue nil
        if doc && doc.css('rcode') && doc.css('rcode')[0].content.to_i >= 100
          Rails.logger.error("Turnitin API error for account_id #{@account_id}: error #{doc.css('rcode')[0].content}")
          Rails.logger.error(params.to_json)
          Rails.logger.error(res.body)
        end
        doc
      end
    end
  end
end
