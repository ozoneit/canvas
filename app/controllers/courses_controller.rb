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

# @API Courses
#
# API for accessing course information.
class CoursesController < ApplicationController
  before_filter :require_user, :only => [:index]
  before_filter :require_user_for_context, :only => [:roster, :roster_user, :locks, :switch_role]

  # @API
  # Returns the list of active courses for the current user.
  #
  # @argument enrollment_type [optional, "teacher"|"student"|"ta"|"observer"|"designer"]
  #   When set, only return courses where the user is enrolled as this type. For
  #   example, set to "teacher" to return only courses where the user is
  #   enrolled as a Teacher.
  #
  # @argument include[] ["needs_grading_count"] Optional information to include with each Course.
  #   When needs_grading_count is given, and the current user has grading
  #   rights, the total number of submissions needing grading for all
  #   assignments is returned.
  #
  # @response_field id The unique identifier for the course.
  # @response_field name The name of the course.
  # @response_field course_code The course code.
  # @response_field enrollments A list of enrollments linking the current user
  #   to the course.
  #
  # @response_field needs_grading_count Number of submissions needing grading
  #   for all the course assignments. Only returned if
  #   include[]=needs_grading_count
  #
  # @example_response
  #   [ { 'id': 1, 'name': 'first course', 'course_code': 'first', 'enrollments': [{'type': 'student'}] },
  #     { 'id': 2, 'name': 'second course', 'course_code': 'second', 'enrollments': [{'type': 'teacher'}] } ]
  def index
    respond_to do |format|
      format.html {
        @current_enrollments = @current_user.cached_current_enrollments(:include_enrollment_uuid => session[:enrollment_uuid]).sort_by{|e| [e.active? ? 1 : 0, e.long_name] }
        @past_enrollments = @current_user.enrollments.ended.scoped(:conditions=>"enrollments.workflow_state NOT IN ('invited', 'deleted')")
      }
      format.json {
        enrollments = @current_user.cached_current_enrollments
        if params[:enrollment_type]
          e_type = "#{params[:enrollment_type].capitalize}Enrollment"
          enrollments = enrollments.reject { |e| e.class.name != e_type }
        end

        include_grading = Array(params[:include]).include?('needs_grading_count')

        hash = []
        enrollments.group_by(&:course_id).each do |course_id, course_enrollments|
          course = course_enrollments.first.course
          hash << course.as_json(
            :include_root => false, :only => %w(id name course_code))
          hash.last['enrollments'] = course_enrollments.map { |e| { :type => e.readable_type.downcase } }
          if include_grading && course_enrollments.any? { |e| e.participating_admin? }
            hash.last['needs_grading_count'] = course.assignments.active.sum('needs_grading_count')
          end
        end
        render :json => hash.to_json
      }
    end
  end
  
  def create
    @account = Account.find(params[:account_id])
    if authorized_action(@account, @current_user, :manage_courses)

      if (sub_account_id = params[:course].delete(:account_id)) && sub_account_id.to_i != @account.id
        @sub_account = @account.find_child(sub_account_id) || raise(ActiveRecord::RecordNotFound)
      end

      if enrollment_term_id = params[:course].delete(:enrollment_term_id)
        params[:course][:enrollment_term] = (@account.root_account || @account).enrollment_terms.find(enrollment_term_id)
      end

      @course = (@sub_account || @account).courses.build(params[:course])
      respond_to do |format|
        if @course.save
          format.html
          format.json { render :json => @course.to_json }
        else
          flash[:error] = "Course creation failed"
          format.html { redirect_to :root_url }
          format.json { render :json => @course.errors.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def backup
    get_context
    if authorized_action(@context, @current_user, :update)
      backup_json = @context.backup_to_json
      send_file_headers!( :length=>backup_json.length, :filename=>"#{@context.name.underscore.gsub(/\s/, "_")}_#{Date.today.to_s}_backup.instructure", :disposition => 'attachment', :type => 'application/instructure')
      render :text => proc {|response, output|
        output.write backup_json
      }
    end
  end
  
  def restore
    get_context
    if authorized_action(@context, @current_user, :update)
      respond_to do |format|
        if params[:restore]
          @context.restore_from_json_backup(params[:restore])
          flash[:notice] = "Backup Successfully Restored!"
          format.html { redirect_to named_context_url(@context, :context_url) }
        else
          format.html
        end
      end
    end
  end

  STUDENT_API_FIELDS = %w(id name)

  # @API
  # Returns the list of sections for this course.
  #
  # @argument include[] ["students"] Associations to include with the group.
  #
  # @response_field id The unique identifier for the course section.
  # @response_field name The name of the section.
  #
  # @example_response
  #   ?include[]=students
  #
  # [
  #   {
  #     "id": 1,
  #     "name": "Section A",
  #     "students": [...]
  #   },
  #   {
  #     "id": 2,
  #     "name": "Section B",
  #     "students": [...]
  #   }
  # ]
  def sections
    get_context
    if authorized_action(@context, @current_user, :read_roster)
      includes = Array(params[:include])
      include_students = includes.include?('students')

      result = @context.course_sections.map do |section|
        res = section.as_json(:include_root => false,
                              :only => %w(id name))
        if include_students
          res['students'] = section.enrollments.all(:conditions => "type = 'StudentEnrollment'").map { |e| e.user.as_json(:include_root => false, :only => STUDENT_API_FIELDS) }
        end
        res
      end

      render :json => result
    end
  end

  # @API
  # Returns the list of students enrolled in this course.
  #
  # @response_field id The unique identifier for the student.
  # @response_field name The full student name.
  #
  # @example_response
  #   [ { 'id': 1, 'name': 'first student' },
  #     { 'id': 2, 'name': 'second student' } ]
  def students
    get_context
    if authorized_action(@context, @current_user, :read_roster)
      render :json => @context.students.to_json(:include_root => false,
                                                :only => STUDENT_API_FIELDS)
    end
  end

  def destroy
    @context = Course.find(params[:id])
    if authorized_action(@context, @current_user, :delete)
      if params[:event] != 'conclude' && (@context.created? || @context.claimed? || params[:event] == 'delete')
        @context.workflow_state = 'deleted'
        @context.save
        flash[:notice] = "Course successfully deleted"
      else
        @context.complete
        flash[:notice] = "Course successfully concluded"
      end
      @current_user.touch
      respond_to do |format|
        format.html {redirect_to dashboard_url}
        format.json {render :json => {:deleted => true}.to_json}
      end
    end
  end
  
  def statistics
    get_context
    if authorized_action(@context, @current_user, :read_reports)
      @student_ids = @context.students.map &:id
      @range_start = Date.parse("Jan 1 2000")
      @range_end = Date.tomorrow
      
      query = "SELECT COUNT(id), SUM(size) FROM attachments WHERE context_id=%s AND context_type='Course' AND root_attachment_id IS NULL AND file_state != 'deleted'"
      row = ActiveRecord::Base.connection.select_rows(query % [@context.id]).first
      @file_count, @files_size = [row[0].to_i, row[1].to_i]
      query = "SELECT COUNT(id), SUM(max_size) FROM media_objects WHERE context_id=%s AND context_type='Course' AND attachment_id IS NULL AND workflow_state != 'deleted'"
      row = ActiveRecord::Base.connection.select_rows(query % [@context.id]).first
      @media_file_count, @media_files_size = [row[0].to_i, row[1].to_i]
      
      if params[:range] && params[:date]
        date = Date.parse(params[:date]) rescue nil
        date ||= Date.today
        if params[:range] == 'week'
          @view_week = (date - 1) - (date - 1).wday + 1
          @range_start = @view_week
          @range_end = @view_week + 6
          @old_range_start = @view_week - 7.days
        elsif params[:range] == 'month'
          @view_month = Date.new(date.year, date.month, d=1) #view.created_at.strftime("%m:%Y")
          @range_start = @view_month
          @range_end = (@view_month >> 1) - 1
          @old_range_start = @view_month << 1
        end
      end
      
      @recently_logged_students = @context.students.recently_logged_in
      respond_to do |format|
        format.html
        format.json{ render :json => @categories.to_json }
      end
    end
  end
  
  def course_details
    get_context
    if authorized_action(@context, @current_user, [:update, :add_students, :add_admin_users])
      add_crumb("Settings", named_context_url(@context, :context_details_url))
      render :action => :course_details
    end
  end
  
  def update_nav
    get_context
    if authorized_action(@context, @current_user, :update)
      @context.tab_configuration = JSON.parse(params[:tabs_json])
      @context.save
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_details_url) }
        format.json { render :json => {:update_nav => true}.to_json }
      end
    end
  end
  
  def roster
    get_context
    if authorized_action(@context, @current_user, :read_roster)
      log_asset_access("roster:#{@context.asset_string}", "roster", "other")
      @students = @context.participating_students.find(:all, :order => 'sortable_name')
      @teachers = @context.admins.find(:all, :order => 'sortable_name')
      @messages = @context.context_messages.find(:all, :order => 'created_at DESC')
      @groups = @context.groups.active
      @categories = @groups.map{|g| g.category}.uniq
    end
  end
  
  def re_send_invitations
    get_context
    if authorized_action(@context, @current_user, [:manage_students, :manage_admin_users])
      @context.detailed_enrollments.each do |e|
        e.re_send_confirmation! if e.invited?
      end
      respond_to do |format|
        format.html { redirect_to course_details_url }
        format.json { render :json => {:re_sent => true}.to_json }
      end
    end
  end
  
  def enrollment_invitation
    get_context
    return if check_enrollment
    if !@pending_enrollment
      redirect_to course_url(@context.id)
      return
    end
    if params[:reject]
      @pending_enrollment.reject!
      session[:enrollment_uuid] = nil
      if @current_user
        flash[:notice] = "Invitation cancelled."  #If you change your mind you can still...
        redirect_to dashboard_url
      else
        flash[:notice] = "Invitation cancelled."
        redirect_to root_url
      end
    elsif params[:accept]
      if @current_user && @pending_enrollment.user == @current_user
        @pending_enrollment.accept!
        session[:accepted_enrollment_uuid] = @pending_enrollment.uuid #session[:enrollment_uuid]
        flash[:notice] = "Invitation accepted!  Welcome to #{@context.name}!"
        redirect_to course_url(@context.id)
      elsif !@current_user && @pending_enrollment.user.registered?
        @pseudonym = @pending_enrollment.user.pseudonym rescue nil
        if @domain_root_account.password_authentication? && @pseudonym
          reset_session
          @pseudonym_session = PseudonymSession.new(@pseudonym, true)
          @pseudonym_session.save!
          redirect_to request.url
        else
          session[:return_to] = course_url(@context.id)
          flash[:notice] = "You'll need to log in before you can accept the enrollment."
          redirect_to login_url
        end
      elsif @current_user && @current_user.registered? && @current_user != @pending_enrollment.user
        if params[:transfer_enrollment]
          @pending_enrollment.user = @current_user
          @pending_enrollment.accept!
          flash[:notice] = "Invitation accepted!  Welcome to #{@context.name}!"
          session[:return_to] = nil
          redirect_to course_url(@context.id)
        else
          session[:return_to] = course_url(@context, :invitation => @pending_enrollment.uuid)
          render :action => "transfer_enrollment"
        end
      else
        user = @pending_enrollment.user
        @pending_enrollment.user.assert_pseudonym_and_communication_channel
        pseudonym = @pending_enrollment.user.pseudonym
        pseudonym.assert_communication_channel if pseudonym
        session[:enrollment_uuid] = @pending_enrollment.uuid
        session[:session_affects_permissions] = true
        session[:to_be_accepted_enrollment_uuid] = session[:enrollment_uuid]
        if @current_user
          redirect_to claim_pseudonym_url(:id => pseudonym.id, :nonce => pseudonym.confirmation_code)
        else
          # pseudonym.assert_communication_channel
          cc = pseudonym.communication_channel || pseudonym.user.communication_channel
          
          redirect_to registration_confirmation_url(pseudonym.id, cc.confirmation_code, :enrollment => @pending_enrollment.uuid)
        end
      end
    else
      redirect_to course_url(@context.id)
    end
  end
  
  def claim_course
    if params[:verification] == @context.uuid
      session[:claim_course_uuid] = @context.uuid
      # session[:course_uuid] = @context.uuid
    end
    if session[:claim_course_uuid] == @context.uuid && @current_user && @context.state == :created
      claim_session_course(@context, @current_user)
    end
  end
  protected :claim_course
  
  def check_enrollment
    enrollment = @context.enrollments.find_by_uuid_and_workflow_state(params[:invitation], "invited")
    enrollment ||= @context.enrollments.find_by_uuid_and_workflow_state(params[:invitation], "rejected")
    if @context_enrollment && @context_enrollment.pending? && !enrollment
      pending_enrollment = @context_enrollment 
      params[:invitation] = pending_enrollment.uuid
      enrollment = pending_enrollment
    end
    if enrollment && enrollment.inactive?
      start_at, end_at = @context.enrollment_dates_for(enrollment)
      if start_at && start_at > Time.now
        flash[:notice] = "You do not have permission to access the course, #{@context.name}, until #{start_at.to_date.to_s}"
      else
        flash[:notice] = "Your membership in the course, #{@context.name}, is not yet activated"
      end
      redirect_to dashboard_url
      return true
    end
    if params[:invitation] && enrollment
      if enrollment.rejected?
        enrollment.workflow_state = 'active'
        enrollment.save_without_broadcasting
      end
      e = enrollment
      session[:enrollment_uuid] = e.uuid
      session[:session_affects_permissions] = true
      session[:enrollment_as_student] = true if e.is_a?(StudentEnrollment)
      session[:enrollment_uuid_course_id] = e.course_id
      if (!@domain_root_account || @domain_root_account.allow_invitation_previews?)
        flash[:notice] = "You've been invited to join this course.  You can look around, but you'll need to accept the enrollment invitation before you can participate."
      elsif params[:action] != "enrollment_invitation"
        redirect_to course_enrollment_invitation_url(@context, :invitation => enrollment.uuid, :accept => 1)
        return true
      end
    end
    if session[:enrollment_uuid] && (e = @context.enrollments.find_by_uuid_and_workflow_state(session[:enrollment_uuid], "invited"))
      @pending_enrollment = e
    end
    if @current_user && @context.enrollments.find_by_user_id_and_workflow_state(@current_user.id, "invited")
      @pending_enrollment = e
    end
    @finished_enrollment = @context.enrollments.find_by_uuid(params[:invitation]) if params[:invitation]
    if session[:accepted_enrollment_uuid] && (e = @context.enrollments.find_by_uuid(session[:accepted_enrollment_uuid]))
      e.accept! if e.invited?
      flash[:notice] = "Invitation accepted!  Welcome to #{@context.name}!"
      session[:accepted_enrollment_uuid] = nil
      session[:enrollment_uuid_course_id] = nil
      session[:enrollment_uuid] = nil if session[:enrollment_uuid] == session[:accepted_enrollment_uuid]
    end
  end
  protected :check_enrollment
  
  def locks
    if authorized_action(@context, @current_user, :read)
      assets = params[:assets].split(",")
      types = {}
      assets.each do |asset|
        split = asset.split("_")
        id = split.pop
        (types[split.join("_")] ||= []) << id
      end
      locks_hash = Rails.cache.fetch(['locked_for_results', @current_user, Digest::MD5.hexdigest(params[:assets])].cache_key) do
        locks = {}
        types.each do |type, ids|
          if type == 'assignment'
            @context.assignments.active.find_all_by_id(ids).compact.each do |assignment|
              locks[assignment.asset_string] = assignment.locked_for?(@current_user)
            end
          elsif type == 'quiz'
            @context.quizzes.active.include_assignment.find_all_by_id(ids).compact.each do |quiz|
              locks[quiz.asset_string] = quiz.locked_for?(@current_user)
            end
          elsif type == 'discussion_topic'
            @context.discussion_topics.active.find_all_by_id(ids).compact.each do |topic|
              locks[topic.asset_string] = topic.locked_for?(@current_user)
            end
          end
        end
        locks
      end
      render :json => locks_hash.to_json
    end
  end
  
  def self_unenrollment
    get_context
    unless @context_enrollment && params[:self_unenrollment] && params[:self_unenrollment] == @context_enrollment.uuid
      redirect_to course_url(@context)
      return
    end
    @context_enrollment.complete
    redirect_to course_url(@context)
  end
  
  def self_enrollment
    get_context
    unless @context.self_enrollment && params[:self_enrollment] && params[:self_enrollment] == @context.self_enrollment_code
      redirect_to course_url(@context)
      return
    end
    if params[:email] || @current_user
      params[:email] ||= @current_user.email
      @user = User.find_by_email(params[:email])
      if @user && @user.registered?
        store_location
        flash[:notice] = "That user already exists.  Please log in before accepting the enrollment."
        redirect_to login_url
        return
      end
      email = (@current_user && @current_user.email) || params[:email]
      @user = @current_user
      email_list = EmailList.new(params[:email])
      @enrollments = EnrollmentsFromEmailList.process(email_list, :course_id => @context.id, :enrollment_type => 'StudentEnrollment', :limit => 1)
      if @enrollments.length == 0
        flash[:error] = "Invalid email address, please try again"
        render :action => 'open_enrollment'
        return
      else
        @enrollment = @enrollments.first
      end
      @enrollment.self_enrolled = true
      @enrollment.accept
      render :action => 'open_enrollment_confirmed'
      # redirect_to course_url(@context, :invitation => @enrollment.uuid)
    else
      render :action => 'open_enrollment'
    end
  end
  
  def check_pending_teacher
    store_location if @context.created?
    if session[:saved_course_uuid] == @context.uuid
      @context_just_saved = true
      session[:saved_course_uuid] = nil
    end
    return unless session[:claimed_course_uuids] && session[:claimed_enrollment_uuids]
    if session[:claimed_course_uuids].include?(@context.uuid)
      session[:claimed_enrollment_uuids].each do |uuid|
        e = @context.enrollments.find_by_uuid(uuid)
        @pending_teacher = e.user if e
      end
    end
  end
  protected :check_pending_teacher
  
  def check_unknown_user
    @public_view = true unless @current_user && @context.grants_right?(@current_user, session, :read_roster)
  end
  protected :check_unknown_user
  
  def show
    @context = Course.find(params[:id])
    @context_enrollment = @context.enrollments.find_by_user_id(@current_user.id) if @context && @current_user
    @unauthorized_message = "The enrollment link you used appears to no longer be valid.  Please contact the course instructor and make sure you're still correctly enrolled." if params[:invitation]
    claim_course if session[:claim_course_uuid] || params[:verification] 
    @context.claim if @context.created?
    return if check_enrollment
    check_pending_teacher
    check_unknown_user
    @user_groups = @current_user.group_memberships_for(@context) if @current_user
    @unauthorized_user = @finished_enrollment.user rescue nil
    if authorized_action(@context, @current_user, :read)
      
      if @current_user && @context.grants_right?(@current_user, session, :manage_grades)
        @assignments_needing_publishing = @context.assignments.active.need_publishing || []
      end
      
      add_crumb(@context.short_name, url_for(@context), :id => "crumb_#{@context.asset_string}")
      
      @course_home_view = (params[:view] == "feed" && 'feed') || @context.default_view || 'feed'
      
      case @course_home_view
      when "wiki"
        @wiki = @context.wiki
        @page = @wiki.wiki_page
      when 'assignments'
        add_crumb("Assignments")
        @contexts = [@context]
        get_sorted_assignments
      when 'modules'
        add_crumb("Modules")
        @modules = ContextModule.fast_cached_for_context(@context)
        @collapsed_modules = ContextModuleProgression.for_user(@current_user).for_modules(@modules).scoped(:select => ['context_module_id, collapsed']).select{|p| p.collapsed? }.map(&:context_module_id)
      when 'syllabus'
        add_crumb("Syllabus")
        @groups = @context.assignment_groups.active.find(:all, :order => 'position, name')
        @events = @context.calendar_events.active.to_a
        @events.concat @context.assignments.active.to_a
        @undated_events = @events.select {|e| e.start_at == nil}
        @dates = (@events.select {|e| e.start_at != nil}).map {|e| e.start_at.to_date}.uniq.sort.sort
      else
        @active_tab = "home"
        @contexts = [@context]
        if @context.grants_right?(@current_user, session, :manage_groups)
          @contexts += @context.groups
        else
          @contexts += @user_groups if @user_groups
        end
        @current_conferences = @context.web_conferences.select{|c| c.active? && c.users.include?(@current_user) }
      end
      
      if @current_user and (@show_recent_feedback = (@current_user.student_enrollments.active.count > 0))
        @recent_feedback = (@current_user && @current_user.recent_feedback(:contexts => @contexts)) || []
      end

      respond_to do |format|
        format.html
        if @context.grants_right?(@current_user, session, :manage_students) || @context.grants_right?(@current_user, session, :manage_admin_users)
          format.json { render :json => @context.to_json(:include => {:current_enrollments => {:methods => :email}}) }
        else
          format.json { render :json => @context.to_json }
        end
      end
    end
  end
  
  def switch_role
    @enrollments = @context.enrollments.scoped({:conditions => ['workflow_state = ?', 'active']}).for_user(@current_user)
    @enrollment = @enrollments.sort_by{|e| [e.state_sortable, e.rank_sortable] }.first
    if params[:role] == 'revert'
      session["role_course_#{@context.id}"] = nil
      flash[:notice] = "Your default role and permissions have been restored"
    elsif (@enrollment && @enrollment.can_switch_to?(params[:role])) || @context.grants_right?(@current_user, session, :manage_admin_users)
      @temp_enrollment = Enrollment.typed_enrollment(params[:role]).new rescue nil
      if @temp_enrollment
        session["role_course_#{@context.id}"] = params[:role]
        session[:session_affects_permissions] = true
        flash[:notice] = "You have switched roles for this course.  You will now see it as if you were a #{@temp_enrollment.readable_type}"
      else
        flash[:error] = "Invalid role type"
      end
    else
      flash[:error] = "You do not have permission to switch roles"
    end
    redirect_to course_url(@context)
  end
  
  def confirm_action
    get_context
    if authorized_action(@context, @current_user, :update)
      params[:event] ||= (@context.claimed? || @context.created? || @context.completed?) ? 'delete' : 'conclude'
    end
  end

  def conclude_user
    get_context
    @enrollment = @context.enrollments.find(params[:id])
    can_remove = @enrollment.is_a?(StudentEnrollment) && @context.grants_right?(@current_user, session, :manage_students)
    can_remove ||= @context.grants_right?(@current_user, session, :manage_admin_users)
    if can_remove
      respond_to do |format|
        if @enrollment.conclude
          format.json { render :json => @enrollment.to_json }
        else
          format.json { render :json => @enrollment.to_json, :status => :bad_request }
        end
      end
    else
      authorized_action(@context, @current_user, :permission_fail)
    end
  end
  
  def unconclude_user
    get_context
    @enrollment = @context.enrollments.find(params[:id])
    can_remove = @enrollment.is_a?(StudentEnrollment) && @context.grants_right?(@current_user, session, :manage_students)
    can_remove ||= @context.grants_right?(@current_user, session, :manage_admin_users)
    if can_remove
      respond_to do |format|
        @enrollment.workflow_state = 'active'
        if @enrollment.save
          format.json { render :json => @enrollment.to_json }
        else
          format.json { render :json => @enrollment.to_json, :status => :bad_request }
        end
      end
    else
      authorized_action(@context, @current_user, :permission_fail)
    end
  end
  
  def limit_user
    get_context
    @user = @context.users.find(params[:id])
    if authorized_action(@context, @current_user, :manage_admin_users)
      if params[:limit] == "1"
        Enrollment.limit_priveleges_to_course_section!(@context, @user, true)
        render :json => {:limited => true}.to_json
      else
        Enrollment.limit_priveleges_to_course_section!(@context, @user, false)
        render :json => {:limited => false}.to_json
      end
    else
      authorized_action(@context, @current_user, :permission_fail)
    end
  end
  
  def unenroll_user
    get_context
    @enrollment = @context.enrollments.find(params[:id])
    can_remove = [StudentEnrollment, ObserverEnrollment].include?(@enrollment.class) && @context.grants_right?(@current_user, session, :manage_students)
    can_remove ||= @context.grants_right?(@current_user, session, :manage_admin_users)
    if can_remove
      respond_to do |format|
        if !@enrollment.defined_by_sis? && @enrollment.destroy
          format.json { render :json => @enrollment.to_json }
        else
          format.json { render :json => @enrollment.to_json, :status => :bad_request }
        end
      end
    else
      authorized_action(@context, @current_user, :permission_fail)
    end
  end

  def enroll_users
    get_context
    params[:enrollment_type] ||= 'StudentEnrollment'
    params[:course_section_id] ||= @context.default_section.id
    can_add = %w(StudentEnrollment ObserverEnrollment).include?(params[:enrollment_type]) && @context.grants_right?(@current_user, session, :manage_students)
    can_add ||= params[:enrollment_type] == 'TeacherEnrollment' && @context.teacherless? && @context.grants_right?(@current_user, session, :manage_students)
    can_add ||= @context.grants_right?(@current_user, session, :manage_admin_users)
    if can_add
      params[:user_emails] ||= ""
      
      email_list = EmailList.new(params[:user_emails])

      respond_to do |format|
        @enrollment_state = nil
        if params[:auto_accept] && @context.account.grants_right?(@current_user, session, :manage_admin_users)
          @enrollment_state = 'active'
        end
        if (@enrollments = EnrollmentsFromEmailList.process(email_list, :course_id => @context.id, :course_section_id => params[:course_section_id], :enrollment_type => params[:enrollment_type], :limit_priveleges_to_course_section => params[:limit_priveleges_to_course_section] == '1', :enrollment_state => @enrollment_state))
          format.json { render :json => @enrollments.to_json(:include => :user, :methods => [:type, :email, :last_name_first, :users_pseudonym_id, :communication_channel_id]) }
        else
          format.json { render :json => "", :status => :bad_request }
        end
      end
    else
      authorized_action(@context, @current_user, :permission_fail)
    end
  end

  def link_enrollment
    get_context
    if authorized_action(@context, @current_user, :manage_admin_users)
      enrollment = @context.observer_enrollments.find(params[:enrollment_id])
      student = nil
      student = @context.students.find(params[:student_id]) if params[:student_id] != 'none'
      enrollment.update_attribute(:associated_user_id, student && student.id)
      render :json => enrollment.to_json(:methods => :associated_user_name)
    end
  end
  
  def copy
    get_context
    if authorized_action(@context, @current_user, :update)
    end
  end
  
  def copy_course
    get_context
    if authorized_action(@context, @current_user, :update)
      args = params[:course].slice(:name, :start_at, :conclude_at)
      account = @context.account
      if params[:course][:account_id]
        account = Account.find(params[:course][:account_id])
        account = nil unless account.grants_right?(@current_user, session, :manage_courses)
      end
      account ||= @domain_root_account.sub_accounts.find_or_create_by_name("Manually-Created Courses")
      if account.grants_right?(@current_user, session, :manage_courses)
        args = params[:course].slice(:name, :start_at, :conclude_at)
        root_account = account.root_account || account
        args[:enrollment_term] = root_account.enrollment_terms.find_by_id(params[:course][:enrollment_term_id])
      end
      args[:enrollment_term] ||= @context.enrollment_term
      args[:abstract_course] = @context.abstract_course
      args[:account] = account
      @course = @context.account.courses.new
      @context.attributes.slice(*Course.clonable_attributes.map(&:to_s)).keys.each do |attr|
        @course.send("#{attr}=", @context.send(attr))
      end
      @course.attributes = args
      @course.workflow_state = 'claimed'
      @course.save
      @course.enroll_user(@current_user, 'TeacherEnrollment', :enrollment_state => 'active')
      redirect_to course_import_copy_url(@course, 'copy[course_id]' => @context.id)
    end
  end

  def update
    @course = Course.find(params[:id])
    if authorized_action(@course, @current_user, :update)
      root_account_id = params[:course].delete :root_account_id
      if root_account_id && current_user_is_site_admin?
        @course.root_account = Account.root_accounts.find(root_account_id)
      end
      if @course.root_account.grants_right?(@current_user, session, :manage)
        if params[:course][:account_id]
          account = Account.find(params[:course].delete(:account_id))
          @course.account = account if account != @course.account && account.grants_right?(@current_user, session, :manage)
        end
        if params[:course][:enrollment_term_id]
          enrollment_term = @course.root_account.enrollment_terms.active.find(params[:course].delete(:enrollment_term_id))
          @course.enrollment_term = enrollment_term if enrollment_term != @course.enrollment_term
        end
      else
        params[:course].delete :account_id
        params[:course].delete :enrollment_term_id
      end
      if !@course.account.grants_right?(@current_user, session, :manage_courses)
        params[:course].delete :storage_quota
        if @course.root_account.settings[:prevent_course_renaming_by_teachers]
          params[:course].delete :name
          params[:course].delete :course_code
        end
      end
      @course.send(params[:course].delete(:event)) if params[:course][:event]
      respond_to do |format|
        @default_wiki_editing_roles_was = @course.default_wiki_editing_roles
        if @course.update_attributes(params[:course])
          @current_user.touch
          if params[:update_default_pages]
            @course.wiki.update_default_wiki_page_roles(@course.default_wiki_editing_roles, @default_wiki_editing_roles_was)
          end
          flash[:notice] = 'Course was successfully updated.'
          format.html { redirect_to((!params[:continue_to] || params[:continue_to].empty?) ? course_url(@course) : params[:continue_to]) }
          format.xml  { head :ok }
          format.json { render :json => @course.to_json(:methods => [:readable_license, :quota, :account_name, :term_name]), :status => :ok }
        else
          format.html { render :action => "edit" }
          format.xml  { render :xml => @course.errors.to_xml }
          format.json { render :json => @course.errors.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def public_feed
    return unless get_feed_context(:only => [:course])
    feed = Atom::Feed.new do |f|
      f.title = "#{@context.name} Feed"
      f.links << Atom::Link.new(:href => named_context_url(@context, :context_url))
      f.updated = Time.now
      f.id = named_context_url(@context, :context_url)
    end
    @entries = []
    @entries.concat @context.assignments.active
    @entries.concat @context.calendar_events.active
    @entries.concat @context.discussion_topics.active.reject{|a| a.locked_for?(@current_user, :check_policies => true) }
    @entries.concat WikiNamespace.default_for_context(@context).wiki.wiki_pages.select{|p| !p.new_record?}
    @entries = @entries.sort_by{|e| e.updated_at}
    @entries.each do |entry|
      feed.entries << entry.to_atom(:context => @context)
    end
    respond_to do |format|
      format.atom { render :text => feed.to_xml }
    end
  end
end
