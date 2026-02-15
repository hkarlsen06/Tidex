
-- Re-add indexes to cover foreign keys on feedback table
CREATE INDEX idx_feedback_user_id ON public.feedback (user_id);
CREATE INDEX idx_feedback_responded_by ON public.feedback (responded_by);
;
