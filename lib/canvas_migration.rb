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

require 'json'
require 'time'
require 'set'
require 'zip/zip'
require 'net/http'
require 'uri'
require 'cgi'
require 'nokogiri'

require 'canvas_migration/migration_worker'
require 'canvas_migration/canvas_migration'
require 'canvas_migration/migrator_helper'
require 'canvas_migration/migrator'
require 'canvas_migration/xml_helper'
