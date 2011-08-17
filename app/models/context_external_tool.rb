class ContextExternalTool < ActiveRecord::Base
  include Workflow
  has_many :content_tags, :as => :content
  belongs_to :context, :polymorphic => true
  attr_accessible :privacy_level, :domain, :url, :shared_secret, :consumer_key, :name, :description, :custom_fields
  validates_presence_of :name
  validates_presence_of :consumer_key
  validates_presence_of :shared_secret
  
  before_save :infer_defaults
  adheres_to_policy
  
  workflow do
    state :anonymous
    state :name_only
    state :public
    state :deleted
  end
  
  set_policy do 
    given { |user, session| self.cached_context_grants_right?(user, session, :update) }
    set { can :read and can :update and can :delete }
  end
  
  def settings
    read_attribute(:settings) || write_attribute(:settings, {})
  end
  
  def readable_state
    workflow_state.titleize
  end
  
  def privacy_level=(val)
    if ['anonymous', 'name_only', 'public'].include?(val)
      self.workflow_state = val
    end
  end
  
  def custom_fields=(hash)
    settings[:custom_fields] ||= {}
    hash.each do |key, val|
      settings[:custom_fields][key] = val if key.match(/\Acustom_/)
    end
  end
  
  def shared_secret=(val)
    write_attribute(:shared_secret, val) unless val.blank?
  end
  
  def infer_defaults
    url = nil if url.blank?
    domain = nil if domain.blank?
  end
  
  def self.standardize_url(url)
    return "" if url.empty?
    url = "http://" + url unless url.match(/:\/\//)
    res = URI.parse(url).normalize
    res.query = res.query.split(/&/).sort.join('&') if !res.query.blank?
    res.to_s
  end
  
  alias_method :destroy!, :destroy
  def destroy
    self.workflow_state = 'deleted'
    save!
  end
  
  def include_email?
    public?
  end
  
  def include_name?
    name_only? || public?
  end
  
  def precedence
    if domain
      # Somebody tell me if we should be expecting more than
      # 25 dots in a url host...
      25 - domain.split(/\./).length
    elsif url
      25
    else
      26
    end
  end
  
  def matches_url?(url)
    if !defined?(@standard_url)
      @standard_url = !self.url.blank? && ContextExternalTool.standardize_url(self.url)
    end
    return true if url == @standard_url
    host = URI.parse(url).host rescue nil
    !!(host && ('.' + host).match(/\.#{domain}\z/))
  end
  
  def self.all_tools_for(context)
    contexts = []
    tools = []
    while context
      if context.is_a?(Group)
        contexts << context
        context = context.context || context.account
      elsif context.is_a?(Course)
        contexts << context
        context = context.account
      elsif context.is_a?(Account)
        contexts << context
        context = context.parent_account
      else
        context = nil
      end
    end
    return nil if contexts.empty?
    contexts.each do |context|
      tools += context.context_external_tools.active
    end
    tools.sort_by(&:name)
  end
  
  # Order of precedence: Basic LTI defines precedence as first
  # checking for a match on domain.  Subdomains count as a match 
  # on less-specific domains, but the most-specific domain will 
  # match first.  So awesome.bob.example.com matches an 
  # external_tool with example.com as the domain, but only if 
  # there isn't another external_tool where awesome.bob.example.com 
  # or bob.example.com is set as the domain.  
  # 
  # If there is no domain match then check for an exact url match
  # as configured by an admin.  If there is still no match
  # then check for a match on the current context (configured by
  # the teacher).
  def self.find_external_tool(url, context)
    url = ContextExternalTool.standardize_url(url)
    account_contexts = []
    other_contexts = []
    while context
      if context.is_a?(Group)
        other_contexts << context
        context = context.context || context.account
      elsif context.is_a?(Course)
        other_contexts << context
        context = context.account
      elsif context.is_a?(Account)
        account_contexts << context
        context = context.parent_account
      else
        context = nil
      end
    end
    return nil if account_contexts.empty? && other_contexts.empty?
    account_contexts.each do |context|
      res = context.context_external_tools.active.sort_by(&:precedence).detect{|tool| tool.domain && tool.matches_url?(url) }
      return res if res
    end
    account_contexts.each do |context|
      res = context.context_external_tools.active.sort_by(&:precedence).detect{|tool| tool.matches_url?(url) }
      return res if res
    end
    other_contexts.reverse.each do |context|
      res = context.context_external_tools.active.sort_by(&:precedence).detect{|tool| tool.matches_url?(url) }
      return res if res
    end
    nil
  end
  
  named_scope :active, :conditions => ['context_external_tools.workflow_state != ?', 'deleted']
  
  def self.serialization_excludes; [:shared_secret,:settings]; end
end
