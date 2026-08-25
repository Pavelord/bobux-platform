-- Bobux map asset storage.
-- Run this on the live Supabase project before publishing maps with many tracks.

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('map-assets', 'map-assets', true, 52428800)
ON CONFLICT (id) DO UPDATE
SET
	public = EXCLUDED.public,
	file_size_limit = EXCLUDED.file_size_limit;

DO $$
BEGIN
	EXECUTE 'DROP POLICY IF EXISTS "Map asset public read" ON storage.objects';

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can read their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can read their own map assets"
			ON storage.objects
			FOR SELECT
			TO authenticated
			USING (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can upload their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can upload their own map assets"
			ON storage.objects
			FOR INSERT
			TO authenticated
			WITH CHECK (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can update their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can update their own map assets"
			ON storage.objects
			FOR UPDATE
			TO authenticated
			USING (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)
			WITH CHECK (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_policies
		WHERE schemaname = 'storage'
			AND tablename = 'objects'
			AND policyname = 'Users can delete their own map assets'
	) THEN
		EXECUTE 'CREATE POLICY "Users can delete their own map assets"
			ON storage.objects
			FOR DELETE
			TO authenticated
			USING (
				bucket_id = ''map-assets''
				AND (storage.foldername(name))[1] = auth.uid()::text
			)';
	END IF;
END $$;
