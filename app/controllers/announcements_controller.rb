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

class AnnouncementsController < ApplicationController
  before_filter :require_user_for_context, :except => :public_feed
  before_filter { |c| c.active_tab = "announcements" }  
  
  def index
    add_crumb("Announcements")
    return if @context.class.const_defined?('TAB_ANNOUNCEMENTS') && !tab_enabled?(@context.class::TAB_ANNOUNCEMENTS)
    @announcements = @context.active_announcements.paginate(:page => params[:page]).reject{|a| a.locked_for?(@current_user, :check_policies => true) }
    if authorized_action(@context, @current_user, :read)
      log_asset_access("announcements:#{@context.asset_string}", "announcements", "other")
      respond_to do |format|
        format.html { render }
        format.json  { render :json => @announcements.to_json(:methods => [:user_name, :discussion_subentry_count], :permissions => {:user => @current_user, :session => session }) }
      end
    end
  end
  
  def show
    redirect_to named_context_url(@context, :context_discussion_topic_url, params[:id])
  end
  
  
  def public_feed
    return unless get_feed_context
    announcements = @context.announcements.active.find(:all, :order => 'created_at DESC', :limit => 15).reject{|a| a.locked_for?(@current_user, :check_policies => true) }
    respond_to do |format|
      format.atom { 
        feed = Atom::Feed.new do |f|
          f.title = "#{@context.name} Announcements Feed"
          f.links << Atom::Link.new(:href => named_context_url(@context, :context_announcements_url))
          f.updated = Time.now
          f.id = named_context_url(@context, :context_announcements_url)
        end
        announcements.each do |e|
          feed.entries << e.to_atom
        end
        render :text => feed.to_xml 
      }
      format.rss { 
        @announcements = announcements
        require 'rss/2.0'
        rss = RSS::Rss.new("2.0")
        channel = RSS::Rss::Channel.new
        channel.title = "#{@context.name} Announcements Podcast Feed"
        channel.description = "Any media files linked from or embedded within announcements in the #{@context.class.to_s.downcase} \"#{@context.name}\" will appear in this feed."
        channel.link = named_context_url(@context, :context_announcements_url)
        channel.pubDate = Time.now.strftime("%a, %d %b %Y %H:%M:%S %z")
        elements = Announcement.podcast_elements(announcements, @context)
        elements.each do |item|
          channel.items << item
        end
        rss.channel = channel
        render :text => rss.to_s
      }
    end
  end
  
  def create_external_feed
    if authorized_action(@context.announcements.new, @current_user, :create)
      params[:external_feed].delete(:add_header_match)
      @feed = @context.external_feeds.build(params[:external_feed])
      @feed.feed_purpose = "announcements"
      @feed.user = @current_user
      @feed.feed_type = "rss/atom"
      if @feed.save
        render :json => @feed.to_json
      else
        render :json => @feed.errors.to_json, :response => :bad_request
      end
    end
  end
  
  def destroy_external_feed
    if authorized_action(@context.announcements.new, @current_user, :create)
      @feed = @context.external_feeds.find(params[:id])
      if @feed.destroy
        render :json => @feed.to_json
      else
        render :json => @feed.errors.to_json, :response => :bad_request
      end
    end
  end
end
