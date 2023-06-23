#!/usr/bin/env nu

# list merge requests active in gitlab
export def mr-list [] {
    let issuePattern = "(?P<issue>NO_ISSUE|(\\w+-\\d+))"
    let now = (date now)

    # TODO: [error handling] not in repo

    # Used to match repos
    # TODO [bug]: Not matching the folder name to repo name
    let currentDirectory = (git rev-parse --show-toplevel | split row "/" | last)

    # Gets gitlab merge requests as table
    #   Columns: id, repo, title, targets, isDraft
    let mrList = (glab mr list | lines)

    if ($mrList == 'glab: 404 Project Not Found (HTTP 404)' or ($mrList | is-empty)) {
        print "Error: 404. Not found."
        return null
    }

    let projectId = ($mrList.0 | parse --regex "(on )(?P<project_name>.+)( \\(Page )" | get project_name | first | str replace '/' '%2F')
    let mergeRequests = ($mrList | skip 2 | drop 1 | parse --regex "!(?P<gitlab_id>.+?)\\s+(?P<repo>.+?)!\\d+\\s+(?P<title>.+?)\\t+(?P<targets>.+)" | sort-by gitlab_id | insert isDraft { $in.title | str contains "Draft:" })
    # Remove `Draft: ` prefix from title column
    let mergeRequests = ($mergeRequests | update title { $in | if $in =~ 'Draft: ' { $in | str substring 7.. } else { $in }})
    # Extract jira/issue id from title
    let mergeRequests = ($mergeRequests | insert jira_id { $in.title | parse --regex $issuePattern | get issue | if ($in | length) > 0 { $in.0 } else { "NO_ISSUE" } })
    # Remove issue prefix from title column
    let mergeRequests = ($mergeRequests | update title { $in | str replace $"($issuePattern): " '' })

    # Get each mr details
    let mrDetails = ($mergeRequests | get gitlab_id | par-each { |it| glab api $"/projects/($projectId)/merge_requests/($it)" | from json } | sort-by iid | select state iid merge_error has_conflicts author head_pipeline)
    # Merge mr details
    let mergeRequests = ($mergeRequests | merge $mrDetails)

    # Get each mr discussion
    let mrDiscussions = ($mergeRequests | get gitlab_id | each { |it| glab api $"/projects/($projectId)/merge_requests/($it)/discussions" | from json } | each { |it| if ($it.notes | length) > 0 { ($it.notes | flatten | sort-by --reverse updated_at | first 1 | select updated_at | rename last_comment_at) | into record } else { {last_comment_at: null} }})
    # Merge last discussion update
    let mergeRequests = ($mergeRequests | merge $mrDiscussions)

    let mergeRequests = ($mergeRequests | insert pipeline { $in | if $in.head_pipeline.status == 'success' { $"✅ \((relative-age $in.head_pipeline.finished_at)\)" } else { $"($in.head_pipeline.status) \((relative-age $in.head_pipeline.started_at)\)" } })
    let mergeRequests = ($mergeRequests | select gitlab_id jira_id title isDraft state merge_error has_conflicts author.name last_comment_at pipeline)
    let mergeRequests = ($mergeRequests | update jira_id { $in | if $in =~ 'NO_ISSUE' { '' } else { $in }})
    let mergeRequests = ($mergeRequests | update isDraft { $in | if $in == true { '✏️' } else { '' }})
    let mergeRequests = ($mergeRequests | update author_name { $in | if $in =~ 'Larus Thor Johannsson' { '@me' } else { $in }})
    # NOTE (LÞJ): Maybe we can merge `merge_error` and `has_conflicts` to a column showing any blockers
    # TODO (LÞJ): Missing "ready to be merged" state
    let mergeRequests = ($mergeRequests | update has_conflicts { $in | if $in == true { '❌' } else { '✅' }})
    # TODO (LÞJ): Maybe show who made the comment?
    let mergeRequests = ($mergeRequests | update last_comment_at { $in | relative-age $in})
    return $mergeRequests
}

# Returns the relative age based on now
export def relative-age [date: string] {
    if $date == null { return '' }
    let duration = (date now) - ($date | into datetime)
    let durationRecord = ($duration | into record)
    if ('year' in $durationRecord) {
        return $">($durationRecord.year) yrs"
    }
    if ('month' in $durationRecord) {
        return $">($durationRecord.month) mth"
    }
    if ('day' in $durationRecord) {
        return $">($durationRecord.day) days"
    }
    if ('hour' in $durationRecord) {
        return $">($durationRecord.hour) hrs"
    }
    if ('minute' in $durationRecord) {
        return $">($durationRecord.minute) mins"
    }
    return $duration
}
