/// The device-proven still-live-with-stack query. Emits ONE column named
/// `row`: the 9 fields joined by U+001F, ordered by (callsiteId, depth).
///
/// Verbatim — proven working on-device against a real heapprofd trace via
/// `trace_processor_shell -q`. Do not reformat or "clean up" the SQL; even
/// harmless-looking whitespace/formatting changes risk altering behavior
/// that hasn't been re-validated on device.
const String kStillLiveWithStackSql = """
with recursive
agg as (
  select callsite_id,
    sum(case when size  > 0 then size  else 0 end) as alloc_bytes,
    sum(case when count > 0 then count else 0 end) as alloc_count,
    sum(case when size  < 0 then -size  else 0 end) as free_bytes,
    sum(case when count < 0 then -count else 0 end) as free_count
  from heap_profile_allocation
  group by callsite_id
  having alloc_bytes > 0
),
chain(root_callsite, id, frame_id, parent_id, depth) as (
  select a.callsite_id, c.id, c.frame_id, c.parent_id, 0
  from agg a join stack_profile_callsite c on c.id = a.callsite_id
  union all
  select ch.root_callsite, c.id, c.frame_id, c.parent_id, ch.depth + 1
  from stack_profile_callsite c join chain ch on c.id = ch.parent_id
)
select
  ch.root_callsite || char(31) || ch.depth || char(31) ||
  coalesce(spf.name,'') || char(31) || coalesce(spm.name,'') || char(31) ||
  coalesce(spm.build_id,'') || char(31) ||
  a.alloc_bytes || char(31) || a.alloc_count || char(31) ||
  a.free_bytes  || char(31) || a.free_count as row
from chain ch
join agg a on a.callsite_id = ch.root_callsite
join stack_profile_frame spf on ch.frame_id = spf.id
left join stack_profile_mapping spm on spf.mapping = spm.id
order by ch.root_callsite, ch.depth;
""";
