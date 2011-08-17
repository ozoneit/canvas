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

class AssignmentsController < ApplicationController
  include GoogleDocs
  before_filter :require_context
  add_crumb("Assignments", :except => [:destroy, :syllabus, :index]) { |c| c.send :course_assignments_path, c.instance_variable_get("@context") }
  before_filter { |c| c.active_tab = "assignments" }
  
  def index
    if @context == @current_user || authorized_action(@context, @current_user, :read)
      get_all_pertinent_contexts
      get_sorted_assignments
      add_crumb("Assignments", (@just_viewing_one_course ? named_context_url(@context, :context_assignments_url) : "/assignments" ))
      @context= (@just_viewing_one_course ? @context : @current_user)
      return if @just_viewing_one_course && !tab_enabled?(@context.class::TAB_ASSIGNMENTS)

      respond_to do |format|
        if @contexts.empty?
          if @context
            format.html { redirect_to @context == @current_user ? dashboard_url : named_context_url(@context, :context_url) }
          else
            format.html { redirect_to root_url }
          end
        elsif @just_viewing_one_course && @context.assignments.new.grants_right?(@current_user, session, :update)
          format.html
        else
          @current_user_submissions ||= @current_user && @current_user.submissions.scoped(:select => 'id, assignment_id, score, workflow_state', :conditions => {:assignment_id => @upcoming_assignments.map(&:id)}) 
          format.html { render :action => "student_index" }
        end
        format.xml  { render :xml => @assignments.to_xml }
        # TODO: eager load the rubric associations
        format.json { render :json => @assignments.to_json(:include => [ :rubric_association, :rubric ]) }
      end
    end
  end
  
  def show
    @assignment ||= @context.assignments.find(params[:id])
    if @assignment.deleted?
      respond_to do |format|
        flash[:notice] = "This assignment has been deleted"
        format.html { redirect_to named_context_url(@context, :context_assignments_url) }
      end
      return
    end
    if authorized_action(@assignment, @current_user, :read)
      @assignment_groups = @context.assignment_groups.active
      if !@assignment.new_record? && !@assignment_groups.map(&:id).include?(@assignment.assignment_group_id)
        @assignment.assignment_group = @assignment_groups.first
        @assignment.save
      end
      @locked = @assignment.locked_for?(@current_user, :check_policies => true, :deep_check_if_needed => true)
      @unlocked = !@locked || @assignment.grants_rights?(@current_user, session, :update)[:update]
      @assignment_module = @assignment.context_module_tag
      @assignment.context_module_action(@current_user, :read) if @unlocked && !@assignment.new_record?
      if @assignment.grants_right?(@current_user, session, :grade)
        student_ids = @context.students.map(&:id)
        @current_student_submissions = @assignment.submissions.having_submission.select{|s| student_ids.include?(s.user_id) }
      end
      if @assignment.grants_right?(@current_user, session, :read_own_submission) && @context.grants_right?(@current_user, session, :read_grades)
        @current_user_submission = @assignment.submissions.find_by_user_id(@current_user.id) if @current_user
        @current_user_submission = nil if @current_user_submission && !@current_user_submission.grade && !@current_user_submission.submission_type
        @current_user_rubric_assessment = @assignment.rubric_association.rubric_assessments.find_by_user_id(@current_user.id) if @current_user && @assignment.rubric_association
        @current_user_submission.send_later(:context_module_action) if @current_user_submission
      end
      if @assignment.submission_types && @assignment.submission_types.match(/online_upload/)
        # TODO: make this happen asynchronously via ajax, and only if the user selects the google docs tab
        @google_docs = google_doc_list(nil, @assignment.allowed_extensions) rescue nil
      end
      
      if @assignment.new_record?
        add_crumb("New Assignment", request.url)
      else
        add_crumb(@assignment.title, named_context_url(@context, :context_assignment_url, @assignment))
      end
      log_asset_access(@assignment, "assignments", @assignment_group) unless @assignment.new_record?
      respond_to do |format|
        if @assignment.submission_types == 'online_quiz' && @assignment.quiz && !@editing
          format.html { redirect_to named_context_url(@context, :context_quiz_url, @assignment.quiz.id) }
        elsif @assignment.submission_types == 'discussion_topic' && @assignment.discussion_topic && !@editing
          format.html { redirect_to named_context_url(@context, :context_discussion_topic_url, @assignment.discussion_topic.id) }
        elsif @assignment.submission_types == 'attendance' && !@editing
          format.html { redirect_to named_context_url(@context, :context_attendance_url, :anchor => "assignment/#{@assignment.id}") }
        else
          format.html { render :action => 'show' }
        end
        format.xml  { render :xml => @assignment.to_xml }
        format.json { render :json => @assignment.to_json(:permissions => {:user => @current_user, :session => session}) }
      end
    end
  end
  
  def rubric
    @assignment = @context.assignments.active.find(params[:assignment_id])
    if authorized_action(@assignment, @current_user, :read)
      render :partial => 'shared/assignment_rubric_dialog'
    end
  end
  
  def assign_peer_reviews
    @assignment = @context.assignments.active.find(params[:assignment_id])
    if authorized_action(@assignment, @current_user, :grade)
      cnt = params[:peer_review_count].to_i
      @assignment.peer_review_count = cnt if cnt > 0
      @assignment.assign_peer_reviews
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_assignment_peer_reviews_url, @assignment.id) }
      end
    end
  end
  
  def assign_peer_review
    @assignment = @context.assignments.active.find(params[:assignment_id])
    @student = @context.students_visible_to(@current_user).find params[:reviewer_id]
    @reviewee = @context.students_visible_to(@current_user).find params[:reviewee_id]
    if authorized_action(@assignment, @current_user, :grade)
      @request = @assignment.assign_peer_review(@student, @reviewee)
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_assignment_peer_reviews_url, @assignment.id) }
        format.json { render :json => @request.to_json(:methods => :asset_user_name) }
      end
    end
  end
  
  def remind_peer_review
    @assignment = @context.assignments.active.find(params[:assignment_id])
    if authorized_action(@assignment, @current_user, :grade)
      @request = AssessmentRequest.find_by_id(params[:id])
      respond_to do |format|
        if @request.asset.assignment == @assignment && @request.send_reminder!
          format.html { redirect_to named_context_url(@context, :context_assignment_peer_reviews_url) }
          format.json { render :json => @request.to_json }
        else
          format.html { redirect_to named_context_url(@context, :context_assignment_peer_reviews_url) }
          format.json { render :json => {:errors => {:base => "Reminder failed"}}.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def delete_peer_review
    @assignment = @context.assignments.active.find(params[:assignment_id])
    if authorized_action(@assignment, @current_user, :grade)
      @request = AssessmentRequest.find_by_id(params[:id])
      respond_to do |format|
        if @request.asset.assignment == @assignment && @request.destroy
          format.html { redirect_to named_context_url(@context, :context_assignment_peer_reviews_url) }
          format.json { render :json => @request.to_json }
        else
          format.html { redirect_to named_context_url(@context, :context_assignment_peer_reviews_url) }
          format.json { render :json => {:errors => {:base => "Delete failed"}}.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def peer_reviews
    @assignment = @context.assignments.active.find(params[:assignment_id])
    if authorized_action(@assignment, @current_user, :grade)
      if !@assignment.has_peer_reviews?
        redirect_to named_context_url(@context, :context_assignment_url, @assignment.id)
        return
      end
      @students = @context.students_visible_to(@current_user)
      @submissions = @assignment.submissions.include_assessment_requests
    end
  end
  
  def syllabus
    return unless tab_enabled?(@context.class::TAB_SYLLABUS)
    add_crumb "Syllabus"
    active_tab = "Syllabus"
    if authorized_action(@context.assignments.new, @current_user, :read)
      @groups = @context.assignment_groups.active.find(:all, :order => 'position, name')
      @assignment_groups = @groups
      @events = @context.calendar_events.active.to_a
      @events.concat @context.assignments.active.to_a
      @undated_events = @events.select {|e| e.start_at == nil}
      @dates = (@events.select {|e| e.start_at != nil}).map {|e| e.start_at.to_date}.uniq.sort.sort
      
      log_asset_access("syllabus:#{@context.asset_string}", "syllabus", 'other')
      respond_to do |format|
        format.html
      end
    end
  end
  
  def new
    if !params[:model_key]
      args = request.query_parameters
      args[:model_key] = rand(999999).to_s
      redirect_to(args)
      return
    end
    @assignment ||= @context.assignments.build
    if params[:model_key] && session["assignment_#{params[:model_key]}"]
      @assignment = @context.assignments.find_by_id(session["assignment_#{params[:model_key]}"])
    else
      @assignment.title = params[:title]
      @assignment.due_at = params[:due_at]
      @assignment.points_possible = params[:points_possible]
      @assignment.assignment_group_id = params[:assignment_group_id]
      @assignment.submission_types = params[:submission_types]
    end
    if authorized_action(@assignment, @current_user, :create)
      @assignment.title = params[:title]
      @assignment.due_at = params[:due_at]
      @assignment.assignment_group_id = params[:assignment_group_id]
      @assignment.submission_types = params[:submission_types]
      @editing = true
      params[:redirect_to] ||= named_context_url(@context, :context_assignments_url)
      show
    end
  end
  
  def create
    params[:assignment][:time_zone_edited] = Time.zone.name if params[:assignment]
    group = get_assignment_group(params[:assignment])
    if params[:model_key] && session["assignment_#{params[:model_key]}"]
      @assignment = @context.assignments.find_by_id(session["assignment_#{params[:model_key]}"])
      @assignment.attributes = params[:assignment] if @assignment
    end
    @assignment ||= @context.assignments.build(params[:assignment])
    @assignment.workflow_state = "available"
    @assignment.content_being_saved_by(@current_user)
    @assignment.assignment_group = group if group
    # if no due_at was given, set it to 11:59 pm in the creator's time zone
    @assignment.infer_due_at
    if authorized_action(@assignment, @current_user, :create)
      respond_to do |format|
        if @assignment.save
          if params[:model_key]
            session["assignment_#{params[:model_key]}"] = @assignment.id
          end
          flash[:notice] = 'Assignment was successfully created.'
          format.html { redirect_to named_context_url(@context, :context_assignment_url, @assignment.id) }
          format.xml  { head :created, :location => named_context_url(@context, :context_assignment_url, @assignment.id) }
          format.json { render :json => @assignment.to_json(:permissions => {:user => @current_user, :session => session}), :status => :created}
        else
          format.html { render :action => "new" }
          format.xml  { render :xml => @assignment.errors.to_xml }
          format.json { render :json => @assignment.errors.to_json, :status => :bad_request }
        end
      end
    end
  end
  
  def edit
    @assignment = @context.assignments.active.find(params[:id])
    if authorized_action(@assignment, @current_user, :update_content)
      @editing = true
      params[:return_to] = nil
      if @assignment.grants_right?(@current_user, session, :update)
        @assignment.title = params[:title] if params[:title]
        @assignment.due_at = params[:due_at] if params[:due_at]
        @assignment.submission_types = params[:submission_types] if params[:submission_types]
        @assignment.assignment_group_id = params[:assignment_group_id] if params[:assignment_group_id]
      end
      show
    end
  end

  def update
    @assignment = @context.assignments.find(params[:id])
    if authorized_action(@assignment, @current_user, :update_content)
      params[:assignment][:time_zone_edited] = Time.zone.name if params[:assignment]
      if !@assignment.grants_rights?(@current_user, session, :update)[:update]
        p = {}
        p[:description] = params[:assignment][:description]
        params[:assignment] = p
      else
        params[:assignment] ||= {}
        if params[:assignment][:default_grade]
          params[:assignment][:overwrite_existing_grades] = (params[:assignment][:overwrite_existing_grades] == "1")
          @assignment.set_default_grade(params[:assignment])
          render :json => @assignment.submissions.to_json(:include => :quiz_submission)
          return
        end
        params[:assignment].delete :default_grade
        params[:assignment].delete :overwrite_existing_grades
        if params[:publish]
          @assignment.workflow_state = 'published'
        elsif params[:unpublish]
          @assignment.workflow_state = 'available'
        end
        if params[:assignment_type] == "quiz"
          params[:assignment][:submission_types] = "online_quiz"
        elsif params[:assignment_type] == "attendance"
          params[:assignment][:submission_types] = "attendance"
        elsif params[:assignment_type] == "discussion_topic"
          params[:assignment][:submission_types] = "discussion_topic"
        end
      end
      respond_to do |format|
        @assignment.content_being_saved_by(@current_user)
        group = get_assignment_group(params[:assignment])
        @assignment.assignment_group = group if group
        if @assignment.update_attributes(params[:assignment])
          log_asset_access(@assignment, "assignments", @assignment_group, 'participate')
          @assignment.context_module_action(@current_user, :contributed)
          @assignment.reload
          flash[:notice] = 'Assignment was successfully updated.'
          format.html { redirect_to named_context_url(@context, :context_assignment_url, @assignment) }
          format.xml  { head :ok }
          format.json { render :json => @assignment.to_json(:permissions => {:user => @current_user, :session => session}, :methods => [:readable_submission_types], :include => [:quiz, :discussion_topic]), :status => :ok }
        else
          format.html { render :action => "edit" }
          format.xml  { render :xml => @assignment.errors.to_xml }
          format.json { render :json => @assignment.errors.to_json, :status => :bad_request }
        end
      end
    end
  end

  def destroy
    @assignment = Assignment.find(params[:id])
    if authorized_action(@assignment, @current_user, :delete)
      @assignment.destroy

      respond_to do |format|
        format.html { redirect_to(named_context_url(@context, :context_assignments_url)) }
        format.xml  { head :ok }
        format.json { render :json => @assignment.to_json }
      end
    end
  end
  
  protected

  def get_assignment_group(assignment_params)
    return unless assignment_params
    if group_id = assignment_params.delete(:assignment_group_id)
      group = @context.assignment_groups.find(group_id)
    end
  end
end
