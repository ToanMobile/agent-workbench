# Luật duyệt approved-head dùng chung (#227, #605): super-board-merge-queue.sh và review_approved_head của super-board-run.sh.
# Vào: JSON `gh pr view <PR> --json comments`. Ra (jq -r): rỗng = không có duyệt; `ok<TAB><sha>`; `bad<TAB><sha><TAB><lý do>`.
# Comment approved-head MỚI NHẤT của OWNER/MEMBER/COLLABORATOR thắng, rồi mới xét nguồn của chính comment đó (marker sai không
# lùi về duyệt cũ hơn). Có dòng `approved-by:` → phải là object JSON với reviewer, builder, task_id, gate_receipt không rỗng và
# reviewer khác builder (không phân biệt hoa thường), 4 trường đều là chuỗi. Không có dòng đó (bare) → chỉ nhận khi comment là của
# OWNER (chủ repo gõ tay); bare của MEMBER/COLLABORATOR → `bad` "approved-by required" (#605 Lane H: tài khoản có quyền ghi khác,
# kể cả bot, không lách được kiểm reviewer ≠ builder).
# So sánh sha với head PR do script gọi làm.
def nonempty: type == "string" and (gsub("^\\s+|\\s+$"; "") | length) > 0;
def norm: tostring | gsub("^\\s+|\\s+$"; "") | ascii_downcase;
[.comments[]? | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR")
  | (.body // "") as $b | .authorAssociation as $assoc
  | ($b | capture("(?m)^approved-head:(?<sha>[0-9a-f]{40})[ \\t\\r]*$")? // empty)
  | {sha, body: $b, assoc: $assoc}]
| last // empty
| . as $a
| ([$a.body | capture("(?m)^approved-by:[ \\t]*(?<j>[^\\n]*)$")?] | first) as $m
| if $m == null then (if $a.assoc == "OWNER" then "ok\t\($a.sha)" else "bad\t\($a.sha)\tapproved-by required (bare approved-head only from the OWNER)" end)
  else (try ($m.j | gsub("\\s+$"; "") | fromjson) catch null) as $o
  | if ($o | type) != "object" then "bad\t\($a.sha)\tapproved-by is not a JSON object"
    elif ([$o.reviewer, $o.builder, $o.task_id, $o.gate_receipt] | all(nonempty) | not)
      then "bad\t\($a.sha)\tapproved-by needs non-empty reviewer, builder, task_id and gate_receipt"
    elif ($o.reviewer | norm) == ($o.builder | norm)
      then "bad\t\($a.sha)\tapproved-by is a self-review (reviewer == builder \($o.reviewer | tostring))"
    else "ok\t\($a.sha)" end
  end
