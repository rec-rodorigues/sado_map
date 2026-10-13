-- =========================================================
-- 元に戻す：2026-10-13_public_edit_and_maps.sql を実行する前の状態へ
--
-- ・「RECメンバーだけ編集できる」元のルールを復元します
-- ・用途別マップ（maps テーブルと spots.map_id）を削除します
--   ※スポットと写真そのものは消えません。別々のマップに入れていた
--     スポットは、すべて1枚の地図にまとめて表示されるようになります。
--
-- サイト側も元に戻す場合は、Git で before-public-edit タグの
-- 状態に戻してください。
-- =========================================================

begin;

-- 1. 新しいルールを外す
do $$
declare
    p record;
begin
    for p in
        select policyname, tablename
        from pg_policies
        where schemaname = 'public'
          and tablename in ('maps', 'spots', 'spot_images')
    loop
        execute format('drop policy %I on public.%I', p.policyname, p.tablename);
    end loop;

    for p in
        select policyname
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and (coalesce(qual, '') || coalesce(with_check, '')) like '%spot-images%'
    loop
        execute format('drop policy %I on storage.objects', p.policyname);
    end loop;
end $$;

-- 2. 保存しておいた元のルールを作り直す
do $$
declare
    p record;
    role_list text;
    sql text;
begin
    for p in
        select *
        from map_backup.policies_20261013
    loop
        select string_agg(
                   case when r = 'public' then 'public' else quote_ident(r) end,
                   ', '
               )
        into role_list
        from unnest(p.roles) as r;

        sql := format(
            'create policy %I on %I.%I as %s for %s to %s',
            p.policyname,
            p.schemaname,
            p.tablename,
            p.permissive,
            p.cmd,
            coalesce(role_list, 'public')
        );

        if p.qual is not null then
            sql := sql || ' using (' || p.qual || ')';
        end if;

        if p.with_check is not null then
            sql := sql || ' with check (' || p.with_check || ')';
        end if;

        execute sql;
    end loop;
end $$;

-- 3. 追加した関数・列・テーブルを削除する
drop function if exists public.is_spot_folder_editable(text);
drop function if exists public.is_spot_editable(bigint);
drop function if exists public.is_map_unlocked(bigint);
drop function if exists public.is_map_admin();

drop index if exists public.spots_map_id_idx;
alter table public.spots drop column if exists map_id;
drop table if exists public.maps;

commit;

-- 元のルールのバックアップ（map_backup スキーマ）は念のため残しています。
-- 不要になったら次の1行で削除できます：
-- drop schema map_backup cascade;
