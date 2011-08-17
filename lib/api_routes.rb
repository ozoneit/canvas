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

# Extend YARD to generate our API documentation
YARD::Tags::Library.define_tag("Is an API method", :API)
YARD::Tags::Library.define_tag("API method argument", :argument)
YARD::Tags::Library.define_tag("API response field", :response_field)
YARD::Tags::Library.define_tag("API example response", :example_response)

module YARD::Templates::Helpers
  module BaseHelper
    def run_verifier(list)
      list.select { |o| relevant_object?(o) }
    end

    def relevant_object?(object)
      case object.type
      when :root, :module, :constant
        false
      when :method, :class
        !object.tags("API").empty?
      else
        if object.parent.nil?
          false
        else
          relevant_object?(object.parent)
        end
      end
    end
  end
end

