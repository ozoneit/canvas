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

require 'rubygems'
require 'net/http'
require 'uri'
require 'nokogiri'
require 'libxml'

# Test Console and API Documentation at:
# http://www.kaltura.com/api_v3/testmeDoc/index.php
module Kaltura
  include Multipart
  class SessionType
    USER = 0;
    ADMIN = 2;
  end
  
  class ClientV3
    attr_accessor :endpoint, :ks
    
    def initialize
      config = Kaltura::ClientV3.config
      @host = config['domain']
      @endpoint = config['endpoint']
      @partnerId = config['partner_id']
      @secret = config['secret_key']
      @user_secret = config['user_secret_key']
      @host ||= "www.kaltura.com"
      @endpoint ||= "/api_v3"
    end
    
    def self.config
      res = Canvas::Plugin.find(:kaltura).try(:settings)
      res = nil unless res && res['partner_id'] && res['subpartner_id']		
      res
    end
    
    def startSession(type = SessionType::USER, userId = nil)
      partnerId = @partnerId
      secret = type == SessionType::USER ? @user_secret : @secret
      result = sendRequest(:session, :start, 
                           :secret => secret,
                           :partnerId => partnerId, 
                           :userId => userId,
                           :type => type)
      @ks = result.content
    end
    
    def mediaGet(entryId)
      result = sendRequest(:media, :get,
                            :ks => @ks,
                            :entryId => entryId)
      item = {}
      result.children.each do |child|
        item[child.name.to_sym] = child.content
      end
      item
    end
    
    def mediaUpdate(entryId, attributes)
      hash = {
        :ks => @ks,
        :entryId => entryId
      }
      attributes.each do |key, val|
        hash["mediaEntry:#{key}"] = val
      end
      result = sendRequest(:media, :update, hash)
      item = {}
      result.children.each do |child|
        item[child.name.to_sym] = child.content
      end
      item
    end
    
    def mediaDelete(entryId)
      hash = {
        :ks => @ks,
        :entryId => entryId
      }
      result = sendRequest(:media, :delete, hash)
      result
    end
    
    def mediaTypeToSymbol(type)
      case type.to_i
      when 1
        :video
      when 2
        :image
      when 5
        :audio
      else
        :video
      end
    end
    
    def bulkUploadGet(id)
      result = sendRequest(:bulkUpload, :get,
                           :ks => @ks,
                           :id => id
                          )
      parseBulkUpload(result)
    end
    
    def parseBulkUpload(result)
      data = {}
      data[:result] = result
      url = result.css('logFileUrl')[0].content
      csv = FasterCSV.parse(Net::HTTP.get(URI.parse(url)))
      data[:entries] = []
      csv.each do |row|
        data[:entries] << {
          :name => row[0],
          :entryId => row[-3],
          :originalId => row[11]
        }
      end
      data[:id] = result.css('id')[0].content
      data[:status] = result.css('status')[0].content
      data[:ready] = !csv.empty? && csv[0][0] != "Log file is not ready"
      data
    end
    
    def bulkUploadAdd(files)
      rows = []
      files.each do |file|
        filename = (file[:name] || "Media File").gsub(/,/, "")
        description = (file[:description] || "no description").gsub(/,/, "")
        url = file[:url]
        rows << [filename, description, file[:tags] || "", url, file[:media_type] || "video", '', '', '' ,'' ,'' ,'' ,file[:id] || ''].join(',') if file[:url]
      end
      csv = rows.join("\n")
      result = postRequest(:bulkUpload, :add,
                           :ks => @ks,
                           :conversionProfileId => -1,
                           :csvFileData => StringIO.new(rows.join("\r\n"))
                       )
      parseBulkUpload(result)
      # results will have entryId values -- do we get them right away?
    end
    
    def flavorAssetGetByEntryId(entryId)
      result = sendRequest(:flavorAsset, :getByEntryId,
                           :ks => @ks,
                           :entryId => entryId)
      items = []
      result.css('item').each do |node|
        item = {}
        node.children.each do |child|
          item[child.name.to_sym] = child.content
        end
        items << item
      end
      items
    end

    def flavorAssetGetByEntryId(entryId)
      result = sendRequest(:flavorAsset, :getByEntryId,
                           :ks => @ks,
                           :entryId => entryId)
      items = []
      result.css('item').each do |node|
        item = {}
        node.children.each do |child|
          item[child.name.to_sym] = child.content
        end
        items << item
      end
      items
    end
    
    def flavorAssetGetDownloadUrl(assetId)
      result = sendRequest(:flavorAsset, :getDownloadUrl,
                           :ks => @ks,
                           :id => assetId)
      return result.content
    end
    
    def assetSwfUrl(assetId)
      config = Kaltura::ClientV3.config
      return nil unless config
      "http://#{config['domain']}/kwidget/wid/_#{config['partner_id']}/uiconf_id/#{config['player_ui_conf']}/entry_id/#{assetId}"
    end
    
    @private
    
    def postRequest(service, action, params)
      mp = Multipart::MultipartPost.new
      query, headers = mp.prepare_query(params)
      res = nil
      Net::HTTP.start(@host) {|con|
        req = Net::HTTP::Post.new(@endpoint + "/?service=#{service}&action=#{action}", headers)
        con.read_timeout = 30
        begin
          res = con.request(req, query) #con.post(url.path, query, headers)
        rescue => e
          puts "POSTING Failed #{e}... #{Time.now}"
        end
      }      
      doc = Nokogiri::XML(res.body)
      doc.css('result').first
    end
    def sendRequest(service, action, params)
      requestParams = "service=#{service}&action=#{action}"
      params.each do |key, value|
        next if value.nil?
        requestParams += "&#{URI.escape(key.to_s)}=#{URI.escape(value.to_s)}"
      end
      res = Net::HTTP.get_response(@host, "#{@endpoint}/?#{requestParams}")
      doc = Nokogiri::XML(res.body)
      doc.css('result').first
    end
  end
end

