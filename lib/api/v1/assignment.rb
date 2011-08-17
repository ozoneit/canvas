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

module Api::V1::Assignment
  def assignment_json(assignment, includes = [], show_admin_fields = false)
  # no includes supported right now
  hash = assignment.as_json(:include_root => false, :only => %w(id grading_type points_possible position))

  hash['name'] = assignment.title

  if show_admin_fields
    hash['needs_grading_count'] = assignment.needs_grading_count
  end

  hash['submission_types'] = assignment.submission_types.split(',')

  if assignment.rubric_association
    hash['use_rubric_for_grading'] =
      !!assignment.rubric_association.use_for_grading
    if assignment.rubric_association.rubric
      hash['free_form_criterion_comments'] =
        !!assignment.rubric_association.rubric.free_form_criterion_comments
    end
  end

  hash['rubric'] = assignment.rubric.data.map do |row|
    row_hash = row.slice(:id, :points, :description, :long_description)
    row_hash["ratings"] = row[:ratings].map { |c| c.slice(:id, :points, :description) }
    row_hash
  end if assignment.rubric

  if assignment.discussion_topic
    hash['discussion_topic'] = {
      'id' => assignment.discussion_topic.id,
      'url' => named_context_url(assignment.context,
                                 :context_discussion_topic_url,
                                 assignment.discussion_topic,
                                 :include_host => true)
    }
  end

  hash
  end
end
