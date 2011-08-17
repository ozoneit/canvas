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

class Tinychat
  require 'net/http'
  require 'net/https'
  require 'uri'
  
  def self.config
    # Return existing value, even if nil, as long as it's defined
    return @config if defined?(@config)
    @config ||= (YAML.load_file(RAILS_ROOT + "/config/tinychat.yml")[RAILS_ENV] rescue nil)
  end
end