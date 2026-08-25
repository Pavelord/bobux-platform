-- ============================================================================
-- Supabase SQL Migration: Catalog & Avatar Inventory
-- Make sure to run this inside your Supabase SQL Editor.
-- ============================================================================

-- 1. Upgrade the profiles table to manage user inventory and avatar
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_data JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS inventory_items JSONB DEFAULT '[]'::jsonb;

-- 2. Create the global Catalog Items table
CREATE TABLE IF NOT EXISTS public.catalog_items (
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    creator_id UUID REFERENCES auth.users(id),
    price_robux INT DEFAULT 0,
    price_tickets INT DEFAULT 0,
    is_for_sale BOOLEAN DEFAULT true,
    model_url TEXT, -- Path to 3D Godot scene/mesh (.scn / .obj)
    thumbnail_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Note: RLS (Row Level Security)
-- Policies for catalog_items
ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Catalog items are viewable by everyone." 
ON public.catalog_items FOR SELECT USING (true);

-- (Optional) Only admins/creators can Insert/Update, but for now we'll allow authenticated users to test:
CREATE POLICY "Authenticated users can create items." 
ON public.catalog_items FOR INSERT WITH CHECK (auth.uid() = creator_id);

-- Dummy item insertion (so your UI isn't completely empty when testing)
INSERT INTO public.catalog_items (category, name, description, price_robux)
VALUES 
('Accessories', 'Pal Hair', 'A classic classic.', 0),
('Accessories', 'Brown Hair', 'Nice hair.', 10),
('Faces', 'Smile', 'Default smile.', 0),
('Faces', 'Chill', 'Extremely chill.', 20),
('Shirts', 'Blue and Black Motorcycle Shirt', 'Vroom.', 5),
('Pants', 'Dark Green Jeans', 'Jeans.', 5)
ON CONFLICT DO NOTHING;
