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

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  
  attr_accessor :active_tab
  
  add_crumb "home", :root_path, :class => "home"
  helper :all
  filter_parameter_logging :password
  
  include AuthenticationMethods
  protect_from_forgery
  before_filter :load_account, :load_user
  include SslRequirement
  before_filter :set_time_zone
  before_filter :clear_cached_contexts
  before_filter :set_page_view
  after_filter :log_page_view
  after_filter :discard_flash_if_xhr
  after_filter :cache_buster
  before_filter :fix_xhr_requests
  before_filter :init_body_classes_and_active_tab

  ssl_allowed_if(:api_request?)

  protected
  
  def init_body_classes_and_active_tab
    @body_classes = []
    active_tab = nil
  end
  
  # make things requested from jQuery go to the "format.js" part of the "respond_to do |format|" block
  # see http://codetunes.com/2009/01/31/rails-222-ajax-and-respond_to/ for why
  def fix_xhr_requests
    request.format = :js if request.xhr? && request.format == :html
  end
  
  # scopes all time objects to the user's specified time zone
  def set_time_zone
    if @current_user && !@current_user.time_zone.blank?
      Time.zone = @current_user.time_zone
      if Time.zone && Time.zone.name == "UTC" && @current_user.time_zone && @current_user.time_zone.match(/\s/)
        Time.zone = @current_user.time_zone.split(/\s/)[1..-1].join(" ") rescue nil
      end
    else
      Time.zone = @domain_root_account && @domain_root_account.default_time_zone
    end
  end

  # retrieves the root account for the given domain
  def load_account
    @domain_root_account = request.env['canvas.domain_root_account'] || Account.default
    @files_domain = request.host != HostUrl.context_host(@domain_root_account) && request.host == HostUrl.file_host(@domain_root_account)
    @domain_root_account
  end

  # used to generate context-specific urls without having to
  # check which type of context it is everywhere
  def named_context_url(context, name, *opts)
    context = context.user if context.is_a?(UserProfile)
    klass = context.class.base_ar_class
    name = name.to_s.sub(/context/, klass.name.underscore)
    opts.unshift(context)
    opts.push({}) unless opts[-1].is_a?(Hash)
    include_host = opts[-1].delete(:include_host)
    if !include_host
      opts[-1][:host] = context.host_name rescue nil
      opts[-1][:only_path] = true
    end
    self.send name, *opts
  end
  
  def user_url(*opts)
    opts[0] == @current_user && !current_user_is_site_admin? && !@current_user.grants_right?(@current_user, session, :view_statistics) ?
      profile_url :
      super
  end

  def tab_enabled?(id)
    if @context && @context.respond_to?(:tabs_available) && !@context.tabs_available(@current_user, :include_hidden_unused => true).any?{|t| t[:id] == id }
      flash[:notice] = "That page has been disabled for this #{@context.class.to_s.downcase}"
      redirect_to named_context_url(@context, :context_url)
      return false
    end
    true
  end
  
  # checks the authorization policy for the given object using 
  # the vendor/plugins/adheres_to_policy plugin.  If authorized,
  # returns true, otherwise renders unauthorized messages and returns
  # false.  To be used as follows:
  # if authorized_action(object, @current_user, session, :update)
  #   render
  # end
  def authorized_action(object, *opts)
    can_do = is_authorized_action?(object, *opts)
    render_unauthorized_action(object) unless can_do
    can_do
  end
  
  def is_authorized_action?(object, *opts)
    user = opts.shift
    action_session = nil
    action_session ||= session
    action_session = opts.shift if !opts[0].is_a?(Symbol) && !opts[0].is_a?(Array)
    actions = Array(opts.shift)
    can_do = false
    begin
      if object == @context && user == @current_user
        @context_all_permissions ||= @context.grants_rights?(user, session, nil)
        can_do = actions.any?{|a| @context_all_permissions[a] }
      else
        can_do = actions.any?{|a| object.grants_right?(user, action_session, a) }
      end
    rescue => e
      logger.warn "#{object.inspect} raised an error while granting rights.  #{e.inspect}"
    end
    can_do
  end
  
  def render_unauthorized_action(object=nil)
    object ||= User.new
    object.errors.add_to_base("You are not authorized to perform this action")
    respond_to do |format|
      if !request.xhr?
        flash[:notice] = "You are not authorized to perform this action"
      end
      @show_left_side = false
      clear_crumbs
      params = request.path_parameters
      params[:format] = nil
      @headers = !!@current_user if @headers != false
      @files_domain = @account_domain && @account_domain.host_type == 'files'
      format.html { 
        store_location if request.get?
        render :template => "shared/unauthorized", :layout => "application", :status => :unauthorized 
      }
      format.zip { redirect_to(url_for(params)) }
      format.xml { render :xml => { 'status' => 'unauthorized' }, :status => :unauthorized }
      format.json { render :json => { 'status' => 'unauthorized' }, :status => :unauthorized }
    end
    response.headers["Pragma"] = "no-cache"
    response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
  end
  
  # To be used as a before_filter, requires controller or controller actions
  # to have their urls scoped to a context in order to be valid.
  # So /courses/5/assignments or groups/1/assignments would be valid, but
  # not /assignments
  def require_context
    get_context
    if !@context
      if request.path.match(/\A\/profile/)
        store_location
        redirect_to login_url
      elsif params[:context_id]
        raise ActiveRecord::RecordNotFound.new("Cannot find #{params[:context_type] || 'Context'} for ID: #{params[:context_id]}")
      else
        raise ActiveRecord::RecordNotFound.new("Context is required, but none found")
      end
    end
    return @context != nil
  end
  
  def clean_return_to(url)
    return nil if !url
    uri = URI.parse(url)
    url = uri.path + (uri.query ? "?#{uri.query}" : "") + (uri.fragment ? "##{uri.fragment}" : "")
  end
  helper_method :clean_return_to
  
  def return_to(url, fallback)
    url = fallback if url.blank?
    url = clean_return_to(url)
    redirect_to url
  end
  
  # Can be used as a before_filter, or just called from controller code.
  # Assigns the variable @context to whatever context the url is scoped
  # to.  So /courses/5/assignments would have a @context=Course.find(5).
  # Also assigns @context_membership to the membership type of @current_user
  # if @current_user is a member of the context.
  def get_context
    unless @context
      if params[:course_id]
        @context = Course.find(params[:course_id])
        params[:context_id] = params[:course_id]
        params[:context_type] = "Course"
        if @context && session[:enrollment_uuid_course_id] == @context.id
          session[:enrollment_uuid_count] ||= 0
          if session[:enrollment_uuid_count] > 4
            session[:enrollment_uuid_count] = 0
            flash[:html_notice] = "You'll need to <a href='#{course_url(@context)}'>accept the enrollment invitation</a> before you can fully participate in this course."
          end
          session[:enrollment_uuid_count] += 1
        end
        @context_enrollment = @context.enrollments.find_all_by_user_id(@current_user.id).sort_by{|e| [e.state_sortable, e.rank_sortable] }.first if @context && @current_user
        @context_membership = @context_enrollment
      elsif params[:account_id] || (self.is_a?(AccountsController) && params[:account_id] = params[:id])
        @context = Account.find(params[:account_id])
        params[:context_id] = params[:account_id]
        params[:context_type] = "Account"
        @context_enrollment = @context.account_users.find_by_user_id(@current_user.id) if @context && @current_user
        @context_membership = @context_enrollment
        @account = @context
      elsif params[:group_id]
        @context = Group.find(params[:group_id])
        params[:context_id] = params[:group_id]
        params[:context_type] = "Group"
        @context_enrollment = @context.group_memberships.find_by_user_id(@current_user.id) if @context && @current_user      
        @context_membership = @context_enrollment
      elsif params[:user_id]
        @context = User.find(params[:user_id])
        params[:context_id] = params[:user_id]
        params[:context_type] = "User"
        @context_membership = @context if @context == @current_user
      elsif request.path.match(/\A\/profile/) || request.path == '/' || request.path.match(/\A\/dashboard\/files/) || request.path.match(/\A\/calendar/) || request.path.match(/\A\/assignments/) || request.path.match(/\A\/files/)
        @context = @current_user
        @context_membership = @context
      end
      if @context.try_rescue(:only_wiki_is_public) && params[:controller].match(/wiki/) && !@current_user && (!@context.is_a?(Course) || session[:enrollment_uuid_course_id] != @context.id)
        @show_left_side = false
      end
      add_crumb(@context.short_name, named_context_url(@context, :context_url), :id => "crumb_#{@context.asset_string}") if @context && @context.respond_to?(:short_name)
    end
  end
  
  # This is used by a number of actions to retrieve a list of all contexts
  # associated with the given context.  If the context is a user then it will
  # include all the user's current contexts.
  # Assigns it to the variable @contexts
  def get_all_pertinent_contexts(include_groups = false)
    return if @already_ran_get_all_pertinent_contexts
    @already_ran_get_all_pertinent_contexts = true

    raise(ArgumentError, "Need a starting context") if @context.nil?

    @contexts = [@context]
    only_contexts = ActiveRecord::Base.parse_asset_string_list(params[:only_contexts])
    if @context && @context.is_a?(User)
      # we already know the user can read these courses and groups, so skip
      # the grants_right? check to avoid querying for the various memberships
      # again.
      courses = @context.courses.active
      groups = include_groups ? @context.groups.active : []
      if only_contexts.present?
        # find only those courses and groups passed in the only_contexts
        # parameter, but still scoped by user so we know they have rights to
        # view them.
        courses = courses.find_all_by_id(only_contexts.select { |c| c.first == "Course" }.map(&:last))
        groups = groups.find_all_by_id(only_contexts.select { |c| c.first == "Group" }.map(&:last)) if include_groups
      end
      @contexts.concat courses
      @contexts.concat groups
    end
    if params[:include_contexts]
      params[:include_contexts].split(",").each do |include_context|
        # don't load it again if we've already got it
        next if @contexts.any? { |c| c.asset_string == include_context }
        context = Context.find_by_asset_string(include_context)
        @contexts << context if context && context.grants_right?(@current_user, nil, :read)
      end
    end
    @contexts = @contexts.uniq
    Course.require_assignment_groups(@contexts)
    @context_enrollment = @context.membership_for_user(@current_user) if @context.respond_to?(:membership_for_user)
    @context_membership = @context_enrollment
  end

  # Retrieves all assignments for all contexts held in the @contexts variable.
  # Also retrieves submissions and sorts the assignments based on
  # their due dates and submission status for the given user.
  def get_sorted_assignments
    @assignment_groups    = []
    @upcoming_assignments = []
    @assignments          = []
    @submissions          = []
    @overdue_assignments  = []
    @courses = @contexts.select{ |c| c.is_a?(Course) }
    @just_viewing_one_course = @context.is_a?(Course) && @courses.length == 1
    @context_codes = @courses.map(&:asset_string)
    @context = @courses.first
    if @just_viewing_one_course
      @courses.each do |course|
        # if there is just one context this will leave @groups set up for the view group by assignment group
        @groups = course.assignment_groups.active(:include => :active_assignments)
        assignments_for_this_course = @groups.map(&:active_assignments).flatten
        @assignments += assignments_for_this_course
        @upcoming_assignments += assignments_for_this_course.select{ |a| 
          a.due_at && 
          a.due_at <= 1.weeks.from_now && 
          a.due_at >= Time.now
        }
        log_asset_access("assignments:#{course.asset_string}", "assignments", "other")
      end
    else
      @groups = AssignmentGroup.for_context_codes(@context_codes).active(:include => {:active_assignments => {:submissions => {}, :quiz => {}, :discussion_topic => {}} })
      @assignments = Assignment.active.for_context_codes(@context_codes)
      @courses.each do |course|
        log_asset_access("assignments:#{course.asset_string}", "assignments", "other")
      end
    end
    @upcoming_assignments = @assignments.select{|a|
      a.due_at &&
      a.due_at <= 1.weeks.from_now &&
      a.due_at >= Time.now
    }
    @submissions = @current_user.submissions(:include => {:submission_comments => {}, :rubric_assessment => {}}).to_a if @current_user
    @submissions_hash = {}
    @submissions.each{|s|
      @submissions_hash[s.assignment_id] = s
    }
    @ungraded_assignments = @assignments.select{|a| 
      a.grants_right?(@current_user, session, :grade) && 
      a.expects_submission? &&
      a.needs_grading_count > 0
    }
    @assignment_groups = @groups
    @past_assignments = @assignments.select{ |a| a.due_at && a.due_at < Time.now }
    @undated_assignments = @assignments.select{ |a| !a.due_at }
    @past_assignments.each do |assignment|
      submission = @submissions_hash[assignment.id]
      if assignment.overdue? && 
         assignment.expects_submission? && 
         ( !submission || (!submission.has_submission? && !submission.graded?) ) &&
         assignment.grants_right?(@current_user, session, :submit)
      
        @overdue_assignments << assignment
      end
    end
    @future_assignments = @assignments - @past_assignments
    if request.path.match(/\A\/assignments/)
      if @future_assignments.length > 5
        @future_assignments = @future_assignments.select{|a| a.due_at && a.due_at < 2.weeks.from_now }
      else
        @future_assignments = @future_assignments.select{|a| a.due_at && a.due_at < 4.weeks.from_now }
      end
      if @past_assignments.length > 5
        @past_assignments = @past_assignments.select{|a| a.due_at && a.due_at > 2.weeks.ago }
      else
        @past_assignments = @past_assignments.select{|a| a.due_at && a.due_at > 4.weeks.ago }
      end
      @overdue_assignments = @overdue_assignments.select{|a| a.due_at && a.due_at > 2.weeks.ago }
      @ungraded_assignments = @ungraded_assignments.select{|a| a.due_at && a.due_at > 2.weeks.ago }
    end
    
    [@assignments, @upcoming_assignments, @past_assignments, @overdue_assignments, @ungraded_assignments, @undated_assignments].map(&:sort!)
  end
  
  # Calculates the file storage quota for @context
  def get_quota
    @quota = 0
    @quota_used = 0
    return unless @context
    @quota = 50.megabytes
    @quota = @context.quota.megabytes if (@context.respond_to?("quota") && @context.quota)
    @quota_used = 0
    @context.attachments.active.select{|a| !a.root_attachment_id }.each do |a|
      @quota_used += a.size || 0.0
    end
  end
  
  # Renders a quota exceeded message if the @context's quota is exceeded
  def quota_exceeded(redirect=nil)
    redirect ||= root_url
    get_quota
    if response.body.size + @quota_used > @quota
      respond_to do |format|
        flash[:error] = 'Storage quota exceeded' unless request.format.to_s == "text/plain"
        format.html {redirect_to redirect }
        format.json {render :json => {:errors => {:base => "#{@context.class.to_s} storage quota exceeded"}}.to_json }
        format.text {render :json => {:errors => {:base => "#{@context.class.to_s} storage quota exceeded"}}.to_json }
      end
      return true
    end
    false
  end
  
  # Used to retrieve the context from a :feed_code parameter.  These 
  # :feed_code attributes are keyed off the object type and the object's
  # uuid.  Using the uuid attribute gives us an unguessable url so
  # that we can offer the feeds without requiring password authentication.
  def get_feed_context(opts={})
    pieces = params[:feed_code].split("_", 2)
    if params[:feed_code].match(/\Agroup_membership/)
      pieces = ["group_membership", params[:feed_code].split("_", 3)[-1]]
    end
    @context = nil
    @problem = nil
    if pieces[0] == "enrollment"
      @enrollment = Enrollment.find_by_uuid(pieces[1])
      @context_type = "Course"
      if !@enrollment
        @problem = "The verification code does not match any currently enrolled user."
      elsif @enrollment.course && !@enrollment.course.available?
        @problem = "Feeds for this #{@context_type.downcase} cannot be access until it is published."
      end
      @context = @enrollment.course unless @problem
      @current_user = @enrollment.user unless @problem
    elsif pieces[0] == 'group_membership'
      @membership = GroupMembership.find_by_uuid(pieces[1])
      @context_type = "Group"
      if !@membership
        @problem = "The verification code does not match any currently enrolled user."
      elsif @membership.group && !@membership.group.available?
        @problem = "Feeds for this #{@context_type.downcase} cannot be access until it is published."
      end
      @context = @membership.group unless @problem
      @current_user = @membership.user unless @problem
    else
      @context_type = pieces[0].classify
      if Context::ContextTypes.const_defined?(@context_type)
        @context_class = Context::ContextTypes.const_get(@context_type)
        @context = @context_class.find_by_uuid(pieces[1])
      end
      if !@context
        @problem = "The verification code is invalid."
      elsif (!@context.is_public rescue false) && (!@context.respond_to?(:uuid) || pieces[1] != @context.uuid)
        @problem = "The matching #{@context_type.downcase} has gone private, so public feeds like this one will no longer be visible."
      end
      @context = nil if @problem
      @current_user = @context if @context.is_a?(User)
    end
    if !@context || (opts[:only] && !opts[:only].include?(@context.class.to_s.underscore.to_sym))
      @problem ||= "Invalid feed parameters." if (opts[:only] && !opts[:only].include?(@context.class.to_s.underscore.to_sym))
      @problem ||= "Could not find feed."
      @template_format = 'html'
      @template.template_format = 'html'
      render :text => @template.render(:file => "shared/unauthorized_feed", :layout => "layouts/application"), :status => :bad_request # :template => "shared/unauthorized_feed", :status => :bad_request
      return false
    end
    @context
  end

  def discard_flash_if_xhr
    flash.discard if request.xhr? || request.format.to_s == 'text/plain'
  end
  
  def cancel_cache_buster
    @cancel_cache_buster = true
  end
  
  def cache_buster
    # Annoying problem.  If I set the cache-control to anything other than "no-cache, no-store" 
    # then the local cache is used when the user clicks the 'back' button.  I don't know how
    # to tell the browser to ALWAYS check back other than to disable caching...
    return true if @cancel_cache_buster
    response.headers["Pragma"] = "no-cache"
    response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
  end
  
  def clear_cached_contexts
    ActiveRecord::Base.clear_cached_contexts
    RoleOverride.clear_cached_contexts
  end
  
  def set_page_view
    return true if !page_views_enabled?

    ENV['RAILS_HOST_WITH_PORT'] ||= request.host_with_port rescue nil
    # We only record page_views for html page requests coming from within the
    # app, or if coming from a developer api request and specified as a 
    # page_view.
    if (@developer_key && params[:user_request]) || (!@developer_key && @current_user && !request.xhr? && request.method == :get)
      generate_page_view
    end
  end
  
  def generate_page_view
    @page_view = PageView.new(:url => request.url[0,255], :user_id => @current_user.id, :controller => request.path_parameters['controller'], :action => request.path_parameters['action'], :session_id => request.session_options[:id], :developer_key => @developer_key, :user_agent => request.headers['User-Agent'])
    @page_view.interaction_seconds = 5
    @page_view.user_request = true if params[:user_request] || (@current_user && !request.xhr? && request.method == :get)
    @page_view.created_at = Time.now
    @page_view.updated_at = Time.now
    @page_before_render = Time.now.utc
    @page_view.id = $request_context_id
  end
  
  def generate_new_page_view
    return true if !page_views_enabled?

    generate_page_view
    @page_view.generated_by_hand = true
  end

  def disable_page_views
    @log_page_views = false
    true
  end
  
  # Asset accesses are used for generating usage statistics.  This is how
  # we say, "the user just downloaded this file" or "the user just
  # viewed this wiki page".  We can then after-the-fact build statistics
  # and reports from these accesses.  This is currently being used
  # to generate access reports per student per course.
  def log_asset_access(asset, asset_category, asset_group=nil, level=nil, membership_type=nil)
    return unless @current_user && @context && asset
    @accessed_asset = {
      :code => asset.is_a?(String) ? asset : asset.asset_string,
      :group_code => asset_group.is_a?(String) ? asset_group : (asset_group.asset_string rescue 'unknown'),
      :category => asset_category,
      :membership_type => membership_type || (@context_membership && @context_membership.class.to_s rescue nil),
      :level => level
    }
  end
  
  def log_page_view
    return true if !page_views_enabled?

    if @current_user && @log_page_views != false
      if @page_view && @page_view.generated_by_hand
      elsif request.xhr? && params[:page_view_id]
        if PageView.page_view_method != :db
          @page_view = PageView.new { |p| p.request_id = params[:page_view_id] }
        else
          @page_view = PageView.find_by_request_id(params[:page_view_id])
          if @page_view
            response.headers["X-Canvas-Page-View-Id"] = @page_view.id.to_s
          end
        end

        if @page_view
          @page_view.do_update(params.slice(:interaction_seconds, :page_view_contributed))
          @page_view_update = true
        end
      end
      # If we're logging the asset access, and it's either a participatory action
      # or it's not an update to an already-existing page_view.  We check to make sure 
      # it's not an update because if the page_view already existed, we don't want to 
      # double-count it as multiple views when it's really just a single view.
      if @current_user && @accessed_asset && (@accessed_asset[:level] == 'participate' || !@page_view_update)
        @access = AssetUserAccess.find_or_create_by_user_id_and_asset_code(@current_user.id, @accessed_asset[:code])
        @accessed_asset[:level] ||= 'view'
        if @accessed_asset[:level] == 'view'
          @access.view_score ||= 0
          @access.view_score += 1
          @access.action_level ||= 'view'
        elsif @accessed_asset[:level] == 'participate'
          @access.view_score ||= 0
          @access.view_score += 1
          @access.participate_score ||= 0
          @access.participate_score += 1
          @access.action_level = 'participate'
          @page_view.participated = true if @page_view
        elsif @accessed_asset[:level] == 'submit'
          @access.participate_score ||= 0
          @access.participate_score += 1
          @access.action_level = 'participate'
          @page_view.participated = true if @page_view
        end
        @access.asset_category ||= @accessed_asset[:category]
        @access.asset_group_code ||= @accessed_asset[:group_code]
        @access.membership_type ||= @accessed_asset[:membership_type]
        @access.context = @context.is_a?(UserProfile) ? @context.user : @context
        @access.summarized_at = nil
        @access.save
        @page_view.asset_user_access_id = @access.id if @page_view
        @page_view_update = true
      end
      if @page_view && !request.xhr? && request.get? && (response.content_type || "").match(/html/)
        @page_view.context ||= @context rescue nil
        @page_view.account_id = @domain_root_account.id
        @page_view.render_time ||= (Time.now.utc - @page_before_render) rescue nil
        @page_view_update = true
      end
      if @page_view && @page_view_update
        @page_view.store
      end
    else
      @page_view.destroy if @page_view && !@page_view.new_record?
    end
  rescue => e
    logger.error "Pageview error!"
    raise e if Rails.env == 'development'
    true
  end

  # Custom error catching and message rendering.
  def rescue_action_in_public(exception)
    response_code = response_code_for_rescue(exception)
    begin
      @status_code = interpret_status(response_code)
      @status = @status_code
      @status = 'AUT' if exception.is_a?(ActionController::InvalidAuthenticityToken)
      backtrace = exception.backtrace.to_s
      backtrace += "\nREFERRER: #{request.referrer}"
      @error = ErrorReport.create( :backtrace => exception.backtrace, 
                                   :message => exception.to_s, 
                                   :url => request.url, 
                                   :user => @current_user, 
                                   :user_agent => request.headers['User-Agent'], 
                                   :http_env => ErrorReport.useful_http_env_stuff_from_request(request), 
                                   :request_context_id => $request_context_id,
                                   :account => @domain_root_account,
                                   :request_method => request.method )
      @headers = nil
      session[:last_error_id] = @error.id rescue nil
      if request.xhr? || request.format == :text
        render :json => {:errors => {:base => "Unexpected error, ID: #{@error.id rescue "unknown"}"}, :status => @status}, :status => @status_code
      else
        @status = '500' unless File.exists?(File.join('app', 'views', 'shared', 'errors', "#{@status.to_s[0,3]}_message.html.erb"))
        render :template => "shared/errors/#{@status.to_s[0, 3]}_message.html.erb", 
          :layout => 'application', :status => @status, :locals => {:error => @error, :exception => exception, :status => @status}
      end
    rescue => e
      render_optional_error_file response_code_for_rescue(exception)
      ErrorLogging.log_error(:default, {
        "message" => "rendered error page failed unexpectedly",
        "method" => (request.method rescue "none"),
        'referrer' => (request.referrer rescue 'none'),
        'format' => (request.format rescue 'none'),
        'xhr' => (request.xhr? rescue false),
        'user_id' => (@current_user ? @current_user.id : ''),
        "error_id" => (@error ? @error.id : ""),
        "backtrace" => (e.backtrace.join("<br/>\n") rescue "none"),
        "caught_message" => (e.to_s rescue "none"),
        "url" => (request.url rescue "none")
      }) rescue nil
    end
    begin
      type = :default
      type = :not_found if @status == '404 Not Found' && Rails.env == "production"
      ErrorLogging.log_error(type, {
        "status" => (interpret_status(response_code) rescue "none"),
        "message" => (exception.to_s rescue "none"),
        "method" => (request.method rescue "none"),
        'referrer' => request.referrer, 
        'format' => request.format,
        'xhr' => request.xhr?,
        'user_id' => (@current_user ? @current_user.id : ''),
        "error_id" => (@error ? @error.id : ""),
        "backtrace" => (exception.backtrace.join("<br/>\n") rescue "none"),
        "url" => (request.url rescue "none")
      })
    rescue
    end
  end
  
  def local_request?
    false
  end
  
  def claim_session_course(course, user, state=nil)
    e = course.claim_with_teacher(user)
    session[:claimed_enrollment_uuids] ||= []
    session[:claimed_enrollment_uuids] << e.uuid
    session[:claimed_enrollment_uuids].uniq!
    flash[:notice] = "This course is now claimed, and you've been registered as its first teacher."
    if !@current_user && state == :just_registered
      flash[:notice] += "You should receive an email shortly to complete the registration process."
    end
    session[:claimed_course_uuids] ||= []
    session[:claimed_course_uuids] << course.uuid
    session[:claimed_course_uuids].uniq!
    session[:claim_course_uuid] = nil
    session[:course_uuid] = nil
  end

  class InvalidDeveloperAPIKey < ActionController::InvalidAuthenticityToken #:nodoc:
  end
  rescue_responses['ApplicationController::InvalidDeveloperAPIKey'] = rescue_responses['ActionController::InvalidAuthenticityToken']

  # Had to overwrite this method so we can say you don't need to have an
  # authenticity_token if the request is coming from an api request.
  # we also check for the session token not being set at all here, to catch
  # those who have cookies disabled.
  def verify_authenticity_token
    params[request_forgery_protection_token] = params[request_forgery_protection_token].gsub(" ", "+") rescue nil
    if params[:api_key] && api_request?
      @developer_key = DeveloperKey.find_by_api_key(params[:api_key])
      @developer_key || raise(InvalidDeveloperAPIKey)
    elsif protect_against_forgery? &&
          request.method != :get &&
          verifiable_request_format?
      if session[:_csrf_token].nil? && session.empty? && !request.xhr? && !api_request?
        # the session should have the token stored by now, but doesn't? sounds
        # like the user doesn't have cookies enabled.
        redirect_to(login_url(:needs_cookies => '1'))
        return false
      else
        raise(ActionController::InvalidAuthenticityToken) unless form_authenticity_token == form_authenticity_param
      end
    end
  end

  def api_request?
    !!request.path.match(/\A\/api\//)
  end

  def session_loaded?
    session.send(:loaded?) rescue false
  end
  
  # Retrieving wiki pages needs to search either using the id or 
  # the page title.  We've also got it in here to have more than one
  # wiki per context, although we've never actually used that yet.
  # And maybe we won't.  See models/wiki_namespace.rb for more though.
  def get_wiki_page
    page_name = (params[:wiki_page_id] || params[:id] || (params[:wiki_page] && params[:wiki_page][:title]) || "front-page")
    if(params[:format] && !['json', 'html'].include?(params[:format]))
      page_name += ".#{params[:format]}"
      params[:format] = 'html'
    end
    return @page if @page 
    @namespace = WikiNamespace.default_for_context(@context)
    @wiki = @namespace.wiki
    if params[:action] != 'create'
      @page = @wiki.wiki_pages.deleted_last.find_by_url(page_name.to_s) ||
              @wiki.wiki_pages.deleted_last.find_by_url(page_name.to_s.to_url) ||
              @wiki.wiki_pages.find_by_id(page_name.to_i)
    end
    @page ||= @wiki.wiki_pages.build(
      :title => page_name.titleize,
      :url => page_name.to_url
    )
    @page.current_namespace = @namespace
    @page.body = "Welcome to your new #{@context.class.to_s.downcase} wiki!" if page_name == "front-page" && @page.new_record?
  end
  
  def context_wiki_page_url
    page_name = @page.url
    namespace = WikiNamespace.find_by_wiki_id_and_context_id_and_context_type(@page.wiki_id, @context.id, @context.class.to_s)
    page_name = namespace.namespace + page_name if namespace && !namespace.default?
    named_context_url(@context, :context_wiki_page_url, page_name)
  end

  def content_tag_redirect(context, tag, error_redirect_symbol)
    if tag.content_type == 'Assignment'
      redirect_to named_context_url(context, :context_assignment_url, tag.content_id)
    elsif tag.content_type == 'WikiPage'
      redirect_to named_context_url(context, :context_wiki_page_url, tag.content.url)
    elsif tag.content_type == 'Attachment'
      redirect_to named_context_url(context, :context_file_url, tag.content_id)
    elsif tag.content_type == 'Quiz'
      redirect_to named_context_url(context, :context_quiz_url, tag.content_id)
    elsif tag.content_type == 'DiscussionTopic'
      redirect_to named_context_url(context, :context_discussion_topic_url, tag.content_id)
    elsif tag.content_type == 'ExternalUrl'
      @tag = tag
      @module = tag.context_module
      tag.context_module_action(@current_user, :read)
      render :template => 'context_modules/url_show'
    elsif tag.content_type == 'ContextExternalTool'
      @tag = tag
      @tool = ContextExternalTool.find_external_tool(tag.url, context)
      tag.context_module_action(@current_user, :read)
      if !@tool
        flash[:error] = "Couldn't find valid settings for this this link"
        redirect_to named_context_url(context, error_redirect_symbol)
      else
        render :template => 'external_tools/tool_show'
      end
    else
      flash[:error] = "Didn't recognize the item type for this tag"
      redirect_to named_context_url(context, error_redirect_symbol)
    end
  end

  # pass it a context or an array of contexts and it will give you a link to the
  # person's calendar with only those things checked.
  def calendar_url_for(contexts_to_link_to = nil, options={})
    options[:query] ||= {}
    options[:anchor] ||= {}
    contexts_to_link_to = Array(contexts_to_link_to)
    if !contexts_to_link_to.empty? && options[:anchor].is_a?(Hash)
      options[:anchor][:show] = contexts_to_link_to.collect{ |c| 
        "group_#{c.class.to_s.downcase}_#{c.id}" 
      }.join(',')
      options[:anchor] = options[:anchor].to_json
    end
    options[:query][:include_contexts] = contexts_to_link_to.map{|c| c.asset_string}.join(",") unless contexts_to_link_to.empty?
    calendar_url(
      options[:query].merge(options[:anchor].empty? ? {} : {
        :anchor => options[:anchor].unpack('H*').first # calendar anchor is hex encoded
      })
    )
  end

  # pass it a context or an array of contexts and it will give you a link to the
  # person's files browser for the supplied contexts.
  def files_url_for(contexts_to_link_to = nil, options={})
    options[:query] ||= {}
    contexts_to_link_to = Array(contexts_to_link_to)
    unless contexts_to_link_to.empty?
      options[:anchor] = "#{contexts_to_link_to.first.asset_string}"
    end
    options[:query][:include_contexts] = contexts_to_link_to.map{|c| c.asset_string}.join(",") unless contexts_to_link_to.empty?
    url_for(
      options[:query].merge({
        :controller => 'files',
        :action => "full_index",
        }.merge(options[:anchor].empty? ? {} : {
          :anchor => options[:anchor]
        })
      )
    )
  end
  helper_method :calendar_url_for, :files_url_for
  
  def safe_domain_file_url(attachment, host=nil)
    res = "http://#{host || HostUrl.file_host(@domain_root_account || Account.default)}"
    ts, sig = @current_user && @current_user.access_verifier
    res += named_context_url(@context, :context_file_url, attachment.id)
    res += '/' + URI.escape(attachment.full_display_path)
    # add parameters so that the other domain can create a session that 
    # will authorize file access but not full app access.  We need this in 
    # case there are relative URLs in the file that point to other pieces 
    # of content.
    res += "?user_id=#{(@current_user ? @current_user.id : nil)}&ts=#{ts}&verifier=#{sig}"
    res
  end
  helper_method :safe_domain_file_url
  
  def feature_enabled?(feature)
    @features_enabled ||= {}
    feature = feature.to_sym
    return @features_enabled[feature] if @features_enabled[feature] != nil
    @features_enabled[feature] ||= begin
      if [:question_banks].include?(feature)
        true
      elsif feature == :twitter
        !!Twitter.config
      elsif feature == :facebook
        !!(YAML.load_file(Rails.root + "config/facebooker.yml")[Rails.env] rescue nil)
      elsif feature == :linked_in
        !!LinkedIn.config
      elsif feature == :google_docs
        !!GoogleDocs.config
      elsif feature == :etherpad
        !!EtherpadCollaboration.config
      elsif feature == :kaltura
        !!Kaltura::ClientV3.config
      elsif feature == :web_conferences
        !!WebConference.config
      elsif feature == :tinychat
        !!Tinychat.config
      elsif feature == :scribd
        !!ScribdAPI.config
      elsif feature == :lockdown_browser
        Canvas::Plugin.all_for_tag(:lockdown_browser).any? { |p| p.settings[:enabled] }
      else
        !Rails.env.production? || (@current_user && current_user_is_site_admin?)
      end
    end
  end
  helper_method :feature_enabled?
  
  def service_enabled?(service)
    @domain_root_account && @domain_root_account.service_enabled?(service)
  end
  helper_method :service_enabled?
  
  def feature_and_service_enabled?(feature)
    feature_enabled?(feature) && service_enabled?(feature)
  end
  helper_method :feature_and_service_enabled?
  
  def temporary_user_code(generate=true)
    if generate
      session[:temporary_user_code] ||= "tmp_#{Digest::MD5.hexdigest("#{Time.now.to_i.to_s}_#{rand.to_s}")}"
    else
      session[:temporary_user_code]
    end
  end

  # This before_filter can be used to limit access to only site admins.
  # This checks if the user is an admin of the 'Site Admin' account, and has the
  # site_admin permission.
  def require_site_admin
    require_site_admin_with_permission(:site_admin)
  end
  helper_method :current_user_is_site_admin?

  def require_site_admin_with_permission(permission)
    if session[:become_user_id]
      session[:become_user_id] = nil
      @current_user = @real_current_user
    end
    unless current_user_is_site_admin?(permission)
      flash[:error] = "You don't have permission to access that page"
      redirect_to root_url
      return false
    end
  end

  # This checks if the user is an admin of the 'Site Admin' account, and has the
  # specified permission.
  def current_user_is_site_admin?(permission = :site_admin)
    Account.site_admin.grants_right?(@current_user, session, permission)
  end
  helper_method :current_user_is_site_admin?

  def page_views_enabled?
    PageView.page_views_enabled?
  end
  helper_method :page_views_enabled?
end
