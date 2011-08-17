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

class GradebooksController < ApplicationController
  before_filter :require_user_for_context, :except => :public_feed

  add_crumb("Grades", :except => :public_feed) { |c| c.send :named_context_url, c.instance_variable_get("@context"), :context_grades_url }
  before_filter { |c| c.active_tab = "grades" }

  def grade_summary
    # do this as the very first thing, if the current user is a teacher in the course and they are not trying to view another user's grades, redirect them to the gradebook
    if @context.grants_right?(@current_user, nil, :manage_grades) && !params[:id]
      redirect_to named_context_url(@context, :context_gradebook_url)
      return
    end
    
    id = params[:id]
    if !id
      if @context_enrollment && @context_enrollment.is_a?(ObserverEnrollment) && @context_enrollment.associated_user_id
        id = @context_enrollment.associated_user_id
      else
        id = @current_user.id
      end
    end

    @student_enrollment = @context.all_student_enrollments.find_by_user_id(id)
    @student = @student_enrollment && @student_enrollment.user
    if !@student || !@student_enrollment
      authorized_action(nil, @current_user, :permission_fail)
      return
    end
    if authorized_action(@student_enrollment, @current_user, :read_grades)
      log_asset_access("grades:#{@context.asset_string}", "grades", "other")
      respond_to do |format|
        if @student
          add_crumb(@student.name, named_context_url(@context, :context_student_grades_url, @student.id))
          
          @groups = @context.assignment_groups.active
          @assignments = @context.assignments.active.gradeable.find(:all, :order => 'due_at, title') +
            groups_as_assignments(:groups => @groups, :group_percent_string => "%s%% of Final", :total_points_string => '-')
          @submissions = @context.submissions.find(:all, :conditions => ['user_id = ?', @student.id])
          @courses_with_grades = @student.available_courses.select{|c| c.grants_right?(@student, nil, :participate_as_student)}
          format.html { render :action => 'grade_summary' }
        else
          format.html { render :action => 'grade_summary_list' }
        end
      end
    end
  end
  
  def grading_standards
    @current_user_grading_standards = @current_user.sorted_grading_standards rescue []
    render :json => @current_user_grading_standards.to_json(:methods => :display_name)
  end
  
  def grading_rubrics
    @rubric_contexts = @context.rubric_contexts(@current_user)
    if params[:context_code]
      context = @rubric_contexts.detect{|r| r[:context_code] == params[:context_code] }
      @rubric_context = @context
      if context
        @rubric_context = Context.find_by_asset_string(params[:context_code])
      end
      @rubric_associations = @context.sorted_rubrics(@current_user, @rubric_context)
      render :json => @rubric_associations.to_json(:methods => [:context_name], :include => :rubric)
    else
      render :json => @rubric_contexts.to_json
    end
  end

  def submissions_json
    updated = Time.parse(params[:updated]) rescue nil
    updated ||= Time.parse("Jan 1 2000")
    @submissions = @context.submissions.find(:all, :include => [:quiz_submission, :submission_comments, :attachments], :conditions => ['submissions.updated_at > ?', updated]).to_a
    @new_submissions = @submissions
    
    respond_to do |format|
      if @new_submissions.empty?
        format.json { render :json => [].to_json }
      else
        format.json { render :json => @new_submissions.to_json(:include => [:quiz_submission, :submission_comments, :attachments]) }
      end
    end
  end
  protected :submissions_json

  def attendance
    @enrollment = @context.all_student_enrollments.find_by_user_id(params[:user_id])
    @enrollment ||= @context.all_student_enrollments.find_by_user_id(@current_user.id) if !@context.grants_right?(@current_user, session, :manage_grades)
    add_crumb 'Attendance'
    if !@enrollment && @context.grants_right?(@current_user, session, :manage_grades)
      @assignments = @context.assignments.active.select{|a| a.submission_types == "attendance" }
      @students = @context.students_visible_to(@current_user)
      @submissions = @context.submissions
      @at_least_one_due_at = @assignments.any?{|a| a.due_at }
      # Find which assignment group most attendance items belong to,
      # it'll be a better guess for default assignment group than the first
      # in the list...
      @default_group_id = @assignments.to_a.count_per(&:assignment_group_id).sort_by{|id, cnt| cnt }.reverse.first[0] rescue nil
    elsif @enrollment && @enrollment.grants_right?(@current_user, session, :read_grades)
      @assignments = @context.assignments.active.select{|a| a.submission_types == "attendance" }
      @students = @context.students_visible_to(@current_user)
      @submissions = @context.submissions.find_all_by_user_id(@enrollment.user_id)
      @user = @enrollment.user
      render :action => "student_attendance"
      # render student_attendance, optional params[:assignment_id] to highlight and scroll to that particular assignment
    else
      flash[:notice] = "You are not authorized to view attendance for this course"
      redirect_to named_context_url(@context, :context_url)
      # redirect
    end
  end
  
  # GET /gradebooks/1
  # GET /gradebooks/1.xml
  # GET /gradebooks/1.json
  # GET /gradebooks/1.csv
  def show
    if authorized_action(@context, @current_user, :manage_grades)
      return submissions_json if params[:updated] && request.format == :json
      return gradebook_init_json if params[:init] && request.format == :json
      @context.require_assignment_group
      @groups = @context.assignment_groups.active
      @groups_order = {}
      @groups.each_with_index{|group, idx| @groups_order[group.id] = idx }
      @just_assignments = @context.assignments.active.gradeable.find(:all, :order => 'due_at, title').select{|a| @groups_order[a.assignment_group_id] }
      newest = Time.parse("Jan 1 2010")
      @just_assignments = @just_assignments.sort_by{|a| [a.due_at || newest, @groups_order[a.assignment_group_id] || 0, a.position || 0] }
      @assignments = @just_assignments.dup + groups_as_assignments(:groups => @groups)
      @gradebook_upload = @context.build_gradebook_upload      
      @submissions = []
      @submissions = @context.submissions
      @new_submissions = @submissions
      if params[:updated]
        d = DateTime.parse(params[:updated])
        @new_submissions = @submissions.select{|s| s.updated_at > d}
      end
      already_enrolled = {}
      @context.enrollments.each do |e|
        e.destroy if already_enrolled[[e.user_id,e.course_id]]
        already_enrolled[[e.user_id,e.course_id]] = true if e.is_a?(StudentEnrollment)
      end
      @enrollments_hash = {}
      @context.enrollments.sort_by{|e| [e.state_sortable, e.rank_sortable] }.each{|e| @enrollments_hash[e.user_id] ||= e }
      @students = @context.students_visible_to(@current_user).sort_by{|u| u.sortable_name }.uniq
      
      log_asset_access("gradebook:#{@context.asset_string}", "grades", "other")
      respond_to do |format|
        if params[:view] == "simple"
          @headers = false
          format.html { render :action => "show_simple" }
        else
          format.html { render :action => "show" }
        end
        format.csv { 
          headers["Pragma"] = "no-cache"
          headers["Cache-Control"] = "no-cache"
          send_data(
            @context.gradebook_to_csv, 
            :type => "text/csv", 
            :filename => "Grades-" + @context.name.to_s.gsub(/ /, "_") + ".csv", 
            :disposition => "attachment"
          ) 
        }
        format.json  { render :json => @new_submissions.to_json(:include => [:quiz_submission, :submission_comments, :attachments]) }
      end
    end
  end
  
  def gradebook_init_json
    # res = "{"
    if params[:assignments]
      # you need to specify specifically which assignment fields you want returned to the gradebook via json here
      # that makes it so we do a lot less querying to the db, which means less active record instantiation, 
      # which means less AR -> JSON serialization overhead which means less data transfer over the wire and faster request.
      # (in this case, the worst part was the assignment 'description' which could be a massive wikipage)
      render :json => @context.assignments.active.gradeable.scoped(
        :select => ["id", "title", "due_at", "unlock_at", "lock_at", "points_possible", "min_score", "max_score", "mastery_score", "grading_type", "submission_types", "assignment_group_id", "grading_scheme_id", "grading_standard_id", "group_category", "grade_group_students_individually"].join(", ")
      ) + groups_as_assignments
    elsif params[:students]
      # you need to specify specifically which student fields you want returned to the gradebook via json here
      render :json => @context.students_visible_to(@current_user).to_json(:only => ["id", "name", "sortable_name", "short_name"])
    else
      params[:user_ids] ||= params[:user_id]
      user_ids = params[:user_ids].split(",").map(&:to_i) if params[:user_ids]
      assignment_ids = params[:assignment_ids].split(",").map(&:to_i) if params[:assignment_ids]
      # you need to specify specifically which submission fields you want returned to the gradebook here
      scope_options = {
        :select => ["assignment_id", "attachment_id", "grade", "grade_matches_current_submission", "group_id", "has_rubric_assessment", "id", "score", "submission_comments_count", "submission_type", "submitted_at", "url", "user_id"].join(" ,")
      }
      if user_ids && assignment_ids
        @submissions = @context.submissions.scoped(scope_options).find(:all, :conditions => {:user_id => user_ids, :assignment_id => assignment_ids})
      elsif user_ids
        @submissions = @context.submissions.scoped(scope_options).find(:all, :conditions => {:user_id => user_ids})
      else
        @submissions = @context.submissions.scoped(scope_options)
      end
      render :json => @submissions
    end
  end
  protected :gradebook_init_json
  
  def history
    if authorized_action(@context, @current_user, :manage_grades)
      # TODO this whole thing could go a LOT faster if you just got ALL the versions of ALL the submissions in this course then did a ruby sort_by day then grader
      @days = SubmissionList.days(@context)
      respond_to do |format|
        format.html
      end
    end
  end
  
  def update_submission
    if authorized_action(@context, @current_user, :manage_grades)
      submissions = [params[:submission]]
      if params[:submissions]
        submissions = []
        params[:submissions].each do |key, submission|
          submissions << submission
        end
      end
      @submissions = []
      submissions.compact.each do |submission|
        @assignment = @context.assignments.active.find(submission[:assignment_id])
        @user = @context.students_visible_to(@current_user).find(submission[:user_id].to_i)
        submission[:grader] = @current_user
        submission.delete :comment_attachments
        if params[:attachments]
          attachments = []
          params[:attachments].each do |idx, attachment|
            attachment[:user] = @current_user
            attachments << @assignment.attachments.create(attachment)
          end
          submission[:comment_attachments] = attachments
        end
        begin
          # if it's a percentage graded assignment, we need to ensure there's a
          # percent sign on the end. eventually this will probably be done in
          # the javascript.
          if @assignment.grading_type == "percent" && submission[:grade] && submission[:grade] !~ /%\z/
            submission[:grade] = "#{submission[:grade]}%"
          end
          # requires: assignment_id, user_id, and grade or comment
          @submissions += @assignment.grade_student(@user, submission)
        rescue => e
          @error_message = e.to_s
        end
      end
      @submissions = @submissions.reverse.uniq.reverse
      @submissions = nil if @submissions.empty?

      respond_to do |format|
        if @submissions && !@error_message#&& !@submission.errors || @submission.errors.empty?
          flash[:notice] = 'Assignment submission was successfully updated.'
          format.html { redirect_to course_gradebook_url(@assignment.context) }
          format.xml  { head :created, :location => course_gradebook_url(@assignment.context) }
          format.json { 
            render :json => @submissions.to_json(Submission.json_serialization_full_parameters), :status => :created, :location => course_gradebook_url(@assignment.context)
          }
          format.text { 
            render_for_text @submissions.to_json(Submission.json_serialization_full_parameters), :status => :created, :location => course_gradebook_url(@assignment.context)
          }
        else
          flash[:error] = "Submission was unsuccessful: #{@error_message || 'Submission Failed'}"
          format.html { render :action => "show", :course_id => @assignment.context.id }
          format.xml  { render :xml => {:errors => {:base => @error_message}}.to_xml }#@submission.errors.to_xml }
          format.json { render :json => {:errors => {:base => @error_message}}.to_json, :status => :bad_request }
          format.text { render_for_text({:errors => {:base => @error_message}}.to_json) }
        end
      end
    end
  end
  
  def submissions_zip_upload
    @assignment = @context.assignments.active.find(params[:assignment_id])
    if !params[:submissions_zip] || params[:submissions_zip].is_a?(String)
      flash[:error] = "Could not find file to upload"
      redirect_to named_context_url(@context, :context_assignment_url, @assignment.id)
      return
    end
    @comments, @failures = @assignment.generate_comments_from_files(params[:submissions_zip].path, @current_user)
    flash[:notice] = "Files and comments created for #{@comments.length} user submissions"
  end
  
  def speed_grader
    if authorized_action(@context, @current_user, :manage_grades)
      @assignment = @context.assignments.active.find(params[:assignment_id])
      respond_to do |format|
        format.html {
          @headers = false
          log_asset_access("speed_grader:#{@context.asset_string}", "grades", "other")
          render :action => "speed_grader"
        }
        format.json { render :json => @assignment.speed_grader_json }
      end
    end
  end

  def blank_submission
    @headers = false
    render :action => "blank_submission"
  end
  
  def public_feed
    return unless get_feed_context(:only => [:course])
    
    respond_to do |format|
      feed = Atom::Feed.new do |f|
        f.title = "#{@context.name} Gradebook Feed"
        f.links << Atom::Link.new(:href => named_context_url(@context, :context_gradebook_url))
        f.updated = Time.now
        f.id = named_context_url(@context, :context_gradebook_url)
      end
      @context.submissions.each do |e|
        feed.entries << e.to_atom
      end
      format.atom { render :text => feed.to_xml }
    end
  end

  def groups_as_assignments(options = {})
    options[:groups] ||= @context.assignment_groups.active
    options[:group_percent_string] ||= "%s%%"
    options[:total_points_string] ||= "100%"
    options[:groups].map{ |group|
      points_possible = (@context.group_weighting_scheme == "percent") ? options[:group_percent_string] % group.group_weight : nil
      OpenObject.build('assignment', :id => 'group-' + group.id.to_s, :rules => group.rules, :title => group.name, :points_possible => points_possible, :hard_coded => true, :special_class => 'group_total', :assignment_group_id => group.id, :group_weight => group.group_weight, :asset_string => "group_total_#{group.id}")
    } << OpenObject.build('assignment', :id => 'final-grade', :title => 'Total', :points_possible => options[:total_points_string], :hard_coded => true, :special_class => 'final_grade', :asset_string => "final_grade_column")
  end
end
