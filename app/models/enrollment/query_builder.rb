class Enrollment

  class QueryBuilder
    # Generate SQL fragments used to return enrollments in their
    # respective workflow states. Where needed, these consider the state
    # of the course to ensure that students do not see their enrollments
    # on unpublished courses.
    #
    # strict_checks can be used to bypass the course state checks.
    # This is useful in places like the course settings UI, where we use
    # these conditions to search users in the course (rather than as an
    # association on a particular user)
    #
    # the course_workflow_state option can be used to simplify the
    # query when the enrollments are all known to come from one course
    # whose workflow state is already known. when provided, the method may
    # return nil, in which case the condition should be treated as 'always
    # false'
    def initialize(state, options = {})
      @state = state
      @options = options.reverse_merge(strict_checks: true)
      @builders = infer_sub_builders
    end

    def infer_sub_builders
      case @state
      when :current_and_invited
        [
          QueryBuilder.new(:active, @options),
          QueryBuilder.new(:invited, @options)
        ]
      when :current_and_concluded
        [
          QueryBuilder.new(:active, @options),
          QueryBuilder.new(:completed, @options)
        ]
      end
    end

    # returns a relevant conditions string to be used in a query,
    # or nil if the builder's parameters are invalid (e.g. active
    # enrollments in deleted courses)
    def conditions
      return @builders.map(&:conditions).join(" OR ") if @builders

      case @state
      when :active
        if @options[:strict_checks]
          case @options[:course_workflow_state]
          when 'available'
            # all active enrollments in a published and active course count
            "enrollments.workflow_state='active'"
          when 'claimed'
            # student and observer enrollments don't count as active if the
            # course is unpublished
            "enrollments.workflow_state='active' AND enrollments.type IN ('TeacherEnrollment','TaEnrollment','DesignerEnrollment','StudentViewEnrollment')"
          when nil
            # combine the other branches dynamically based on joined course's
            # workflow_state
            "enrollments.workflow_state='active' AND (courses.workflow_state='available' OR courses.workflow_state='claimed' AND enrollments.type IN ('TeacherEnrollment','TaEnrollment','DesignerEnrollment','StudentViewEnrollment'))"
          else
            # never include enrollments from unclaimed/completed/deleted
            # courses
            nil
          end
        else
          case @options[:course_workflow_state]
          when 'deleted'
            # never include enrollments from deleted courses, even without
            # strict checks
            nil
          when nil
            # combine the other branches dynamically based on joined course's
            # workflow_state
            "enrollments.workflow_state='active' AND courses.workflow_state<>'deleted'"
          else
            # all active enrollments in a non-deleted course count
            "enrollments.workflow_state='active'"
          end
        end
      when :invited
        if @options[:strict_checks]
          case @options[:course_workflow_state]
          when 'available'
            # all invited enrollments in a published and active course count
            "enrollments.workflow_state='invited'"
          when 'deleted'
            # never include enrollments from deleted courses
            nil
          when nil
            # combine the other branches dynamically based on joined course's
            # workflow_state
            "enrollments.workflow_state='invited' AND (courses.workflow_state='available' OR courses.workflow_state<>'deleted' AND enrollments.type IN ('TeacherEnrollment','TaEnrollment','DesignerEnrollment','StudentViewEnrollment'))"
          else
            # student and observer enrollments don't count as invited if
            # the course is unclaimed/unpublished/completed
            "enrollments.workflow_state='invited' AND enrollments.type IN ('TeacherEnrollment','TaEnrollment','DesignerEnrollment','StudentViewEnrollment')"
          end
        else
          case @options[:course_workflow_state]
          when 'deleted'
            # never include enrollments from deleted courses
            nil
          when nil
            # combine the other branches dynamically based on joined course's
            # workflow_state
            "enrollments.workflow_state IN ('invited','creation_pending') AND courses.workflow_state<>'deleted'"
          else
            # all invited and creation_pending enrollments in a non-deleted
            # course count
            "enrollments.workflow_state IN ('invited','creation_pending')"
          end
        end
      when :deleted;          "enrollments.workflow_state = 'deleted'"
      when :rejected;         "enrollments.workflow_state = 'rejected'"
      when :completed;        "enrollments.workflow_state = 'completed'"
      when :creation_pending; "enrollments.workflow_state = 'creation_pending'"
      when :inactive;         "enrollments.workflow_state = 'inactive'"
      end
    end
  end
end
