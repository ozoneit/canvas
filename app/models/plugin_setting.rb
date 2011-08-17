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

# == Schema Information
#
# Table name: plugin_settings
#
#  id         :integer(4)      not null, primary key
#  name       :string(255)     default(""), not null
#  settings   :text
#  created_at :datetime
#  updated_at :datetime
#
class PluginSetting < ActiveRecord::Base
  validates_uniqueness_of :name, :if => :validate_uniqueness_of_name?
  before_save :validate_posted_settings
  serialize :settings
  attr_accessor :posted_settings
  attr_writer :plugin

  before_save :encrypt_settings
  
  def validate_uniqueness_of_name?
    true
  end

  def validate_posted_settings
    if @posted_settings
      plugin = Canvas::Plugin.find(name.to_s)
      plugin.validate_settings(self, @posted_settings)
    end
  end

  def plugin
    @plugin ||= Canvas::Plugin.find(name.to_s)
  end

  # dummy value for encrypted fields so that you can still have something in the form (to indicate
  # it's set) and be able to tell when it gets blanked out.
  DUMMY_STRING = "~!?3NCRYPT3D?!~"
  def after_initialize
    if settings && self.plugin && self.plugin.encrypted_settings
      self.plugin.encrypted_settings.each do |key|
        if settings["#{key}_enc".to_sym]
          settings["#{key}_dec".to_sym] = self.class.decrypt(settings["#{key}_enc"], settings["#{key}_salt".to_sym])
          settings[key] = DUMMY_STRING
        end
      end
    end
  end

  def encrypt_settings
    if settings && self.plugin && self.plugin.encrypted_settings
      self.plugin.encrypted_settings.each do |key|
        unless settings[key].blank?
          value = settings.delete(key)
          settings.delete("#{key}_dec".to_sym)
          if value == DUMMY_STRING  # no change, use what was there previously
            settings["#{key}_enc".to_sym] = settings_was["#{key}_enc".to_sym]
            settings["#{key}_salt".to_sym] = settings_was["#{key}_salt".to_sym]
          else
            settings["#{key}_enc".to_sym], settings["#{key}_salt".to_sym] = self.class.encrypt(value)
          end
        end
      end
    end
  end

  def self.settings_for_plugin(name, plugin=nil)
    if plugin_setting = PluginSetting.find_by_name(name.to_s)
      plugin_setting.plugin = plugin
      settings = plugin_setting.settings
    else
      plugin ||= Canvas::Plugin.find(name.to_s)
      raise Canvas::NoPluginError unless plugin
      settings = plugin.default_settings
    end
    
    settings
  end

  def self.encrypt(text)
    Canvas::Security.encrypt_password(text, 'instructure_plugin_setting')
  end

  def self.decrypt(text, salt)
    Canvas::Security.decrypt_password(text, salt, 'instructure_plugin_setting')
  end
end
