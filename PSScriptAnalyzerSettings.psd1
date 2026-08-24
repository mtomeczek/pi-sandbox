@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Private helper functions intentionally use domain-oriented names.
        'PSUseApprovedVerbs',
        'PSUseSingularNouns'
    )
}
