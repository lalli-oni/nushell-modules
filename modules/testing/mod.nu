#!/usr/bin/env nu

export def test-runner [] {
    # TODO: Have some sanity check to see if we should waste time. fx. if there are no js projects
    let config = (npx jest --showConfig | from json).configs.0?
    # TODO: Removed -s flag due to it being unsupported. maybe it was deprecated?
    let tests = (npx jest --listTests | str replace -a $config.rootDir '')
    # Q: Maybe order on last tests run? or based on files modified?
    let choice = ($tests | split row "\n" | sort | str join "\n" | gum choose --no-limit | split row "\n")
    let runPattern = ($choice | str join '|')
    if ($runPattern | is-empty) {
        print "No tests selected. Exiting."
        return
    }
    print $"Test pattern: ($runPattern)"
    # NOTE: jest cli doesn't run silently. reason being that the default reporter does print
    #       afaik there is no way to disable reporters through the cli
    # TODO: progress indicator/running status
    # TODO: allow control over number of repeats
    # TODO: allow control over whether tests are run in parallel or not
    # TODO: allow control over cache
    mut retry = 0
    mut report = null
    while ($retry == 0) {
        $report = (run-tests $runPattern)
        print $"TOTAL ($report.numTotalTestSuites) suites / ($report.numTotalTests) tests"
        # TODO: Removed -s flag due to it being unsupported. maybe it was deprecated?
        print $"PASSED: ($report.testResults | where $it.status == "passed" | get name | str replace -a $config.rootDir '')"
        let failedTests = ($report.testResults | where status != "passed")
        print $failedTests
        if (($failedTests | is-empty) == false) {
            # TODO: Removed -s flag due to it being unsupported. maybe it was deprecated?
            let failedTests = ($failedTests | flatten | flatten | insert short_name { $in.name | str replace -a $config.rootDir '' } | group-by short_name)
            for test in ($failedTests | transpose key value) {
                # TODO: (bug) each assertion can have 1 or more ancestorTitles
                # TODO: (bug) doesnt seem to correctly list passed/failed tests in suite
                print $"\n($test.value | get ancestorTitles | get 0) \(($test.key)\)"
                for assertion in $test.value {
                    if $assertion.status != 'passed' {
                        print $"\t(ansi red_bold)($assertion.title) - ($assertion.status)(ansi reset)"
                    }
                    ansi reset
                }
            }
        }
        $retry = (gum confirm "Rerun test?" | complete).exit_code
    }
    return $report
}

def run-tests [runPattern: string] {
    return (npx jest --json --silent ($runPattern) | from json)
}