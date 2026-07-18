package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const expectationsFile = "conformance/expectations.yaml"

type diagnostic struct {
	Category string
	Severity string
	Path     string
	Message  string
}

func (d diagnostic) String() string {
	return strings.TrimSpace(fmt.Sprintf("%s %s %s %s", d.Severity, d.Category, d.Path, d.Message))
}

type validationResult struct {
	Errors   []diagnostic
	Warnings []diagnostic
}

func (r validationResult) allDiagnostics() []diagnostic {
	out := make([]diagnostic, 0, len(r.Errors)+len(r.Warnings))
	out = append(out, r.Errors...)
	out = append(out, r.Warnings...)
	return out
}

func diagnosticsText(diagnostics []diagnostic) string {
	var lines []string
	for _, diagnostic := range diagnostics {
		lines = append(lines, diagnostic.String())
	}
	return strings.Join(lines, "\n")
}

func main() {
	contextPath := flag.String("context", "", "target context fixture")
	strictWarnings := flag.Bool("strict-warnings", false, "treat warnings as validation failures")
	flag.Parse()

	if flag.NArg() == 0 {
		ok, err := runSuite()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		if !ok {
			os.Exit(1)
		}
		return
	}

	if flag.NArg() != 1 {
		fmt.Fprintln(os.Stderr, "usage: ads-fixture-validator [--strict-warnings] [--context path] [document]")
		os.Exit(2)
	}

	result, err := validateFile(flag.Arg(0), *contextPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	for _, diagnostic := range result.allDiagnostics() {
		fmt.Println(diagnostic.String())
	}

	if len(result.Errors) > 0 || (*strictWarnings && len(result.Warnings) > 0) {
		os.Exit(1)
	}
}

func runSuite() (bool, error) {
	expectationsValue, err := parseYAMLFile(expectationsFile)
	if err != nil {
		return false, err
	}
	expectations, ok := expectationsValue.(map[string]any)
	if !ok {
		return false, fmt.Errorf("%s must contain a mapping", expectationsFile)
	}

	checks := []bool{}

	for _, file := range expectationList(expectations, "schema", "accepts") {
		result, err := validateSchemaFile(file)
		checks = append(checks, printCheck("schema accepts "+file, err == nil && len(result.Errors) == 0, err, result.Errors, nil))
	}

	for _, file := range expectationList(expectations, "schema", "rejects") {
		result, err := validateSchemaFile(file)
		checks = append(checks, printCheck("schema rejects "+file, err == nil && len(result.Errors) > 0, err, result.Errors, nil))
	}

	for _, file := range expectationList(expectations, "conformance", "accepts") {
		result, err := validateFile(file, "")
		checks = append(checks, printCheck("conformance accepts "+file, err == nil && len(result.Errors) == 0, err, result.allDiagnostics(), nil))
	}

	for _, entry := range expectationEntries(expectations, "conformance", "rejects") {
		file := expectationFile(entry, "file")
		expected := expectedDiagnostics(entry)
		result, err := validateFile(file, "")
		ok := err == nil && len(result.Errors) > 0 && containsAllDiagnostics(result.allDiagnostics(), expected)
		checks = append(checks, printCheck("conformance rejects "+file, ok, err, result.allDiagnostics(), expected))
	}

	for _, entry := range expectationEntries(expectations, "conformance", "warns") {
		file := expectationFile(entry, "file")
		expected := expectedDiagnostics(entry)
		result, err := validateFile(file, "")
		ok := err == nil && len(result.Warnings) > 0 && containsAllDiagnostics(result.allDiagnostics(), expected)
		checks = append(checks, printCheck("conformance warns "+file, ok, err, result.allDiagnostics(), expected))
	}

	for _, entry := range expectationEntries(expectations, "targetContexts") {
		context := expectationFile(entry, "context")
		example := expectationFile(entry, "example")
		result := expectationString(entry, "result")
		validation, err := validateFile(example, context)
		label := "target context " + context + " " + result + " " + example

		switch result {
		case "accepts":
			checks = append(checks, printCheck(label, err == nil && len(validation.Errors) == 0, err, validation.allDiagnostics(), nil))
		case "rejects":
			expected := expectedDiagnostics(entry)
			ok := err == nil && len(validation.Errors) > 0 && containsAllDiagnostics(validation.allDiagnostics(), expected)
			checks = append(checks, printCheck(label, ok, err, validation.allDiagnostics(), expected))
		default:
			return false, fmt.Errorf("targetContexts entry has unsupported result %q", result)
		}
	}

	for _, ok := range checks {
		if !ok {
			return false, nil
		}
	}
	return true, nil
}

func validateSchemaFile(path string) (validationResult, error) {
	value, err := parseYAMLFile(path)
	if err != nil {
		return validationResult{}, err
	}
	return validationResult{Errors: validateSchema(value)}, nil
}

func validateFile(documentPath, contextPath string) (validationResult, error) {
	value, err := parseYAMLFile(documentPath)
	if err != nil {
		return validationResult{}, err
	}

	result := validationResult{}
	result.Errors = append(result.Errors, validateSchema(value)...)
	if len(result.Errors) == 0 {
		errors, warnings := validateConformance(value)
		result.Errors = append(result.Errors, errors...)
		result.Warnings = append(result.Warnings, warnings...)
	}

	if contextPath != "" && len(result.Errors) == 0 {
		contextValue, err := parseYAMLFile(contextPath)
		if err != nil {
			return validationResult{}, err
		}
		result.Errors = append(result.Errors, validateTargetContext(value, contextValue)...)
	}

	return result, nil
}

func printCheck(label string, ok bool, err error, diagnostics []diagnostic, expected []string) bool {
	if ok {
		fmt.Println("PASS " + label)
		return true
	}

	fmt.Println("FAIL " + label)
	if err != nil {
		fmt.Println("  error: " + err.Error())
	}
	for _, expected := range expected {
		fmt.Println("  expected diagnostic substring: " + strconv.Quote(expected))
	}
	for _, diagnostic := range diagnostics {
		fmt.Println("  diagnostic: " + diagnostic.String())
	}
	return false
}

func containsAllDiagnostics(diagnostics []diagnostic, expected []string) bool {
	text := diagnosticsText(diagnostics)
	for _, substring := range expected {
		if !strings.Contains(text, substring) {
			return false
		}
	}
	return true
}

func expectationList(root map[string]any, keys ...string) []string {
	value := lookup(root, keys...)
	list, ok := value.([]any)
	if !ok {
		return nil
	}

	var out []string
	for _, entry := range list {
		if text, ok := entry.(string); ok {
			out = append(out, text)
		}
	}
	return out
}

func expectationEntries(root map[string]any, keys ...string) []map[string]any {
	value := lookup(root, keys...)
	list, ok := value.([]any)
	if !ok {
		return nil
	}

	var out []map[string]any
	for _, entry := range list {
		if text, ok := entry.(string); ok {
			out = append(out, map[string]any{"file": text})
			continue
		}
		if mapping, ok := entry.(map[string]any); ok {
			out = append(out, mapping)
		}
	}
	return out
}

func expectationFile(entry map[string]any, key string) string {
	if value, ok := entry[key].(string); ok {
		return value
	}
	return ""
}

func expectationString(entry map[string]any, key string) string {
	if value, ok := entry[key].(string); ok {
		return value
	}
	return ""
}

func expectedDiagnostics(entry map[string]any) []string {
	list, ok := entry["expectedDiagnostics"].([]any)
	if !ok {
		return nil
	}

	var out []string
	for _, value := range list {
		if text, ok := value.(string); ok {
			out = append(out, text)
		}
	}
	return out
}

func validateSchema(value any) []diagnostic {
	root, ok := value.(map[string]any)
	if !ok {
		return []diagnostic{errorDiagnostic("schema-invalid", "$", "document root must be a mapping")}
	}

	var diagnostics []diagnostic
	requiredRoot := []string{"apiVersion", "kind", "metadata", "runtime", "capabilities", "secrets", "security", "approvals", "observability"}
	for _, key := range requiredRoot {
		if _, ok := root[key]; !ok {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$."+key, "missing required root field"))
		}
	}

	if apiVersion := stringAt(root, "apiVersion"); apiVersion != "" && apiVersion != "ads.dev/v1" {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.apiVersion", "apiVersion must be ads.dev/v1"))
	}
	if kind := stringAt(root, "kind"); kind != "" && kind != "AgenticDeployment" {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.kind", "kind must be AgenticDeployment"))
	}

	metadata := mapAt(root, "metadata")
	if metadata != nil {
		if stringAt(metadata, "name") == "" {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.metadata.name", "metadata.name is required"))
		}
		if stringAt(metadata, "owner") == "" {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.metadata.owner", "metadata.owner is required"))
		}
	}

	components := listAt(root, "runtime", "components")
	if components == nil {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.runtime.components", "runtime.components is required"))
	} else if len(components) == 0 {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.runtime.components", "runtime.components must include at least one component"))
	}

	for index, entry := range components {
		component, ok := entry.(map[string]any)
		if !ok {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", fmt.Sprintf("$.runtime.components[%d]", index), "component must be a mapping"))
			continue
		}
		base := fmt.Sprintf("$.runtime.components[%d]", index)
		if stringAt(component, "name") == "" {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", base+".name", "component name is required"))
		}
		if stringAt(component, "type") == "" {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", base+".type", "component type is required"))
		}
		if stringAt(component, "image") == "" && stringAt(component, "externalRef") == "" {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", base, "component must declare image or externalRef"))
		}
		if stringAt(component, "execution", "mode") == "" {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", base+".execution.mode", "component execution.mode is required"))
		}
		for portIndex, portEntry := range listAt(component, "ports") {
			port, ok := portEntry.(map[string]any)
			if !ok {
				continue
			}
			if value, ok := port["containerPort"].(int); ok && (value < 1 || value > 65535) {
				diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", fmt.Sprintf("%s.ports[%d].containerPort", base, portIndex), "containerPort must be between 1 and 65535"))
			}
		}
	}

	if listAt(root, "capabilities", "required") == nil {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.capabilities.required", "capabilities.required is required"))
	}
	if listAt(root, "secrets", "required") == nil {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.secrets.required", "secrets.required is required"))
	}
	if stringAt(root, "security", "defaultSandbox") == "" {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.security.defaultSandbox", "security.defaultSandbox is required"))
	}
	if stringAt(root, "security", "toolPolicy", "default") == "" {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.security.toolPolicy.default", "security.toolPolicy.default is required"))
	}
	if listAt(root, "approvals", "required") == nil {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.approvals.required", "approvals.required is required"))
	}
	if listAt(root, "observability", "metrics", "required") == nil {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.observability.metrics.required", "observability.metrics.required is required"))
	}
	if listAt(root, "observability", "auditEvents", "required") == nil {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.observability.auditEvents.required", "observability.auditEvents.required is required"))
	}

	for index, event := range stringListAt(root, "observability", "auditEvents", "required") {
		if !isAuditEventName(event) {
			diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", fmt.Sprintf("$.observability.auditEvents.required[%d]", index), "audit event must be standard or namespaced: "+event))
		}
	}

	securityDefault := stringAt(root, "security", "outbound", "default")
	networkDefault := stringAt(root, "networking", "egress", "default")
	if securityDefault != "" && networkDefault != "" && securityDefault != networkDefault {
		diagnostics = append(diagnostics, errorDiagnostic("schema-invalid", "$.networking.egress.default", "networking egress default conflicts with security outbound default"))
	}

	return diagnostics
}

func validateConformance(value any) ([]diagnostic, []diagnostic) {
	root, ok := value.(map[string]any)
	if !ok {
		return []diagnostic{errorDiagnostic("schema-invalid", "$", "document root must be a mapping")}, nil
	}

	var errors []diagnostic
	var warnings []diagnostic

	componentNames := map[string]bool{}
	for index, entry := range listAt(root, "runtime", "components") {
		component, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		name := stringAt(component, "name")
		if name == "" {
			continue
		}
		path := fmt.Sprintf("$.runtime.components[%d].name", index)
		if componentNames[name] {
			errors = append(errors, errorDiagnostic("reference-invalid", path, "component name duplicated: "+name))
		}
		componentNames[name] = true
	}

	for componentIndex, entry := range listAt(root, "runtime", "components") {
		component, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		for dependencyIndex, dependency := range stringsFromValue(component["dependsOn"]) {
			if !componentNames[dependency] {
				path := fmt.Sprintf("$.runtime.components[%d].dependsOn[%d]", componentIndex, dependencyIndex)
				errors = append(errors, errorDiagnostic("reference-invalid", path, "unresolved dependency: "+dependency))
			}
		}
	}

	errors = append(errors, dependencyCycleDiagnostics(root)...)
	errors = append(errors, nameNormalizationDiagnostics(root)...)

	for index, capability := range requiredCapabilities(root) {
		for targetIndex, target := range capability.For {
			if !componentNames[target] {
				path := fmt.Sprintf("$.capabilities.required[%d].for[%d]", index, targetIndex)
				errors = append(errors, errorDiagnostic("reference-invalid", path, "capability target component is undeclared: "+target))
			}
		}
	}

	for index, secret := range requiredSecrets(root) {
		for targetIndex, target := range secret.For {
			if !componentNames[target] {
				path := fmt.Sprintf("$.secrets.required[%d].for[%d]", index, targetIndex)
				errors = append(errors, errorDiagnostic("reference-invalid", path, "secret target component is undeclared: "+secret.Name))
			}
		}
	}

	requiredActions := map[string]bool{}
	for _, approvalEntry := range listAt(root, "approvals", "required") {
		if approval, ok := approvalEntry.(map[string]any); ok {
			action := stringAt(approval, "action")
			if action != "" {
				requiredActions[action] = true
			}
		}
	}

	policyDecisionPoints := map[string]bool{}
	for _, pdpEntry := range listAt(root, "approvals", "policyDecisionPoints") {
		pdp, ok := pdpEntry.(map[string]any)
		if !ok {
			continue
		}
		name := stringAt(pdp, "name")
		if name != "" {
			policyDecisionPoints[name] = true
		}
		for _, action := range stringListAt(pdp, "appliesTo") {
			if action != "" && !requiredActions[action] {
				warnings = append(warnings, warningDiagnostic("policy-decision-point-missing", "$.approvals.policyDecisionPoints", "policy decision point appliesTo action is not declared: "+action))
			}
		}
	}

	for index, approvalEntry := range listAt(root, "approvals", "required") {
		approval, ok := approvalEntry.(map[string]any)
		if !ok {
			continue
		}
		mode := stringAt(approval, "mode")
		if mode != "policy" && mode != "policy-and-human" {
			continue
		}
		ref := stringAt(approval, "policyDecisionPointRef")
		action := stringAt(approval, "action")
		if ref == "" {
			path := fmt.Sprintf("$.approvals.required[%d]", index)
			warnings = append(warnings, warningDiagnostic("policy-decision-point-missing", path, "policy approval should reference a policy decision point for action "+action))
			continue
		}
		if !policyDecisionPoints[ref] {
			path := fmt.Sprintf("$.approvals.required[%d].policyDecisionPointRef", index)
			errors = append(errors, errorDiagnostic("policy-decision-point-missing", path, "policy decision point is undeclared: "+ref))
		}
	}

	if images := mapAt(root, "supplyChain", "images"); boolAt(images, "requireDigest") {
		for index, entry := range listAt(root, "runtime", "components") {
			component, ok := entry.(map[string]any)
			if !ok {
				continue
			}
			image := stringAt(component, "image")
			if image != "" && !strings.Contains(image, "@sha256:") {
				path := fmt.Sprintf("$.runtime.components[%d].image", index)
				errors = append(errors, errorDiagnostic("supply-chain-unverified", path, "image must be pinned with a sha256 digest"))
			}
		}
	}

	if extensions := mapAt(root, "extensions"); extensions != nil {
		for key, value := range extensions {
			if !strings.Contains(key, "/") {
				warnings = append(warnings, warningDiagnostic("compatibility-warning", "$.extensions."+key, "extension key is not namespaced"))
				continue
			}
			if extension, ok := value.(map[string]any); ok && boolAt(extension, "required") {
				errors = append(errors, errorDiagnostic("extension-unsupported", "$.extensions."+key, "Required extension is unsupported: "+key))
			}
		}
	}

	for key := range root {
		if !knownRootFields[key] && !strings.Contains(key, "/") {
			warnings = append(warnings, warningDiagnostic("compatibility-warning", "$."+key, "Unknown non-extension root field: "+key))
		}
	}

	if missing := missingAuditEvents(root); len(missing) > 0 {
		warnings = append(warnings, warningDiagnostic("audit-event-missing", "$.observability.auditEvents.required", "missing recommended audit events: "+strings.Join(missing, ", ")))
	}

	if missing := missingThreatModelCoverage(root); len(missing) > 0 {
		warnings = append(warnings, warningDiagnostic("threat-model-incomplete", "$.security.threatModel", "production threat model is incomplete: "+strings.Join(missing, ", ")))
	}

	return errors, warnings
}

func dependencyCycleDiagnostics(root map[string]any) []diagnostic {
	components := listAt(root, "runtime", "components")
	indexes := map[string]int{}
	graph := map[string][]string{}
	for index, entry := range components {
		component, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		name := stringAt(component, "name")
		if name == "" {
			continue
		}
		indexes[name] = index
		graph[name] = stringsFromValue(component["dependsOn"])
	}

	var diagnostics []diagnostic
	visiting := map[string]bool{}
	visited := map[string]bool{}
	reported := map[string]bool{}

	var visit func(string, []string)
	visit = func(name string, stack []string) {
		if visited[name] {
			return
		}
		if visiting[name] {
			cycleStart := 0
			for index, entry := range stack {
				if entry == name {
					cycleStart = index
					break
				}
			}
			cycle := append([]string{}, stack[cycleStart:]...)
			cycle = append(cycle, name)
			keyParts := append([]string{}, cycle...)
			sort.Strings(keyParts)
			key := strings.Join(keyParts, "\x00")
			if !reported[key] {
				reported[key] = true
				path := fmt.Sprintf("$.runtime.components[%d].dependsOn", indexes[name])
				diagnostics = append(diagnostics, errorDiagnostic("reference-invalid", path, "dependsOn cycle detected: "+strings.Join(cycle, " -> ")))
			}
			return
		}

		visiting[name] = true
		for _, dependency := range graph[name] {
			if _, ok := graph[dependency]; ok {
				visit(dependency, append(stack, name))
			}
		}
		visiting[name] = false
		visited[name] = true
	}

	for name := range graph {
		visit(name, nil)
	}

	return diagnostics
}

func nameNormalizationDiagnostics(root map[string]any) []diagnostic {
	var diagnostics []diagnostic
	seen := map[string]string{}
	for index, entry := range listAt(root, "runtime", "components") {
		component, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		name := stringAt(component, "name")
		if name == "" {
			continue
		}
		resourceName := normalizeResourceName(name)
		if previous, ok := seen[resourceName]; ok && previous != name {
			path := fmt.Sprintf("$.runtime.components[%d].name", index)
			diagnostics = append(diagnostics, errorDiagnostic("processor-limitation", path, fmt.Sprintf("component name %q normalizes to colliding resource name %q", name, resourceName)))
			continue
		}
		seen[resourceName] = name
	}
	return diagnostics
}

func normalizeResourceName(name string) string {
	lower := strings.ToLower(name)
	var builder strings.Builder
	lastDash := false
	for _, char := range lower {
		valid := (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char == '-'
		if valid {
			builder.WriteRune(char)
			lastDash = false
			continue
		}
		if !lastDash {
			builder.WriteRune('-')
			lastDash = true
		}
	}
	normalized := strings.Trim(builder.String(), "-")
	if normalized == "" {
		normalized = "ads-resource"
	}
	if len(normalized) > 63 {
		normalized = strings.TrimRight(normalized[:63], "-")
	}
	if normalized == "" {
		return "ads-resource"
	}
	return normalized
}

func validateTargetContext(document, context any) []diagnostic {
	root, ok := document.(map[string]any)
	if !ok {
		return []diagnostic{errorDiagnostic("schema-invalid", "$", "document root must be a mapping")}
	}
	target, ok := context.(map[string]any)
	if !ok {
		return []diagnostic{errorDiagnostic("schema-invalid", "$", "target context root must be a mapping")}
	}

	var diagnostics []diagnostic

	supportedCapabilities := stringSet(stringListAt(target, "capabilities", "supported"))
	for _, capability := range requiredCapabilities(root) {
		if capability.Name != "" && !supportedCapabilities[capability.Name] {
			diagnostics = append(diagnostics, errorDiagnostic("capability-unsupported", "$.capabilities.required", "target context does not support capability: "+capability.Name))
		}
	}

	secretBindings := keySet(mapAt(target, "secrets", "bindings"))
	for _, secret := range requiredSecrets(root) {
		if secret.Name != "" && !secretBindings[secret.Name] {
			diagnostics = append(diagnostics, errorDiagnostic("secret-unbound", "$.secrets.required", "target context has no binding for secret: "+secret.Name))
		}
	}

	handlers := keySet(mapAt(target, "approvals", "handlers"))
	targetPDPs := keySet(mapAt(target, "approvals", "policyDecisionPoints"))
	for index, approvalEntry := range listAt(root, "approvals", "required") {
		approval, ok := approvalEntry.(map[string]any)
		if !ok {
			continue
		}
		mode := stringAt(approval, "mode")
		path := fmt.Sprintf("$.approvals.required[%d]", index)
		if (mode == "human" || mode == "policy-and-human") && !handlers["human"] {
			diagnostics = append(diagnostics, errorDiagnostic("approval-handler-missing", path, "target context has no human approval handler"))
		}
		if (mode == "policy" || mode == "policy-and-human") && !handlers["policy"] {
			diagnostics = append(diagnostics, errorDiagnostic("approval-handler-missing", path, "target context has no policy approval handler"))
		}
		ref := stringAt(approval, "policyDecisionPointRef")
		if (mode == "policy" || mode == "policy-and-human") && ref == "" {
			diagnostics = append(diagnostics, errorDiagnostic("policy-decision-point-missing", path, "policy approval has no policy decision point reference"))
		}
		if ref != "" && !targetPDPs[ref] {
			diagnostics = append(diagnostics, errorDiagnostic("policy-decision-point-missing", path+".policyDecisionPointRef", "target context has no policy decision point: "+ref))
		}
	}

	if boolAt(mapAt(root, "observability", "traces"), "required") && len(listAt(target, "observability", "traces", "sinks")) == 0 {
		diagnostics = append(diagnostics, errorDiagnostic("observability-sink-missing", "$.observability.traces", "target context has no trace sink"))
	}
	if len(stringListAt(root, "observability", "metrics", "required")) > 0 && len(listAt(target, "observability", "metrics", "sinks")) == 0 {
		diagnostics = append(diagnostics, errorDiagnostic("observability-sink-missing", "$.observability.metrics", "target context has no metric sink"))
	}
	if len(stringListAt(root, "observability", "auditEvents", "required")) > 0 && len(listAt(target, "observability", "auditEvents", "sinks")) == 0 {
		diagnostics = append(diagnostics, errorDiagnostic("observability-sink-missing", "$.observability.auditEvents", "target context has no audit-event sink"))
	}

	diagnostics = append(diagnostics, validateNetwork(root, target)...)
	diagnostics = append(diagnostics, validateSecurity(root, target)...)
	diagnostics = append(diagnostics, validateSupplyChain(root, target)...)

	return diagnostics
}

func validateNetwork(root, target map[string]any) []diagnostic {
	var diagnostics []diagnostic

	requiredDefaultDeny := stringAt(root, "security", "outbound", "default") == "deny" || stringAt(root, "networking", "egress", "default") == "deny"
	requiredDestinations := append([]string{}, stringListAt(root, "security", "outbound", "allow")...)
	requiredDestinations = append(requiredDestinations, stringListAt(root, "networking", "egress", "allow")...)
	requiredDestinations = uniqueStrings(requiredDestinations)

	if !requiredDefaultDeny && len(requiredDestinations) == 0 {
		return diagnostics
	}

	egress := mapAt(target, "network", "egress")
	if egress == nil {
		return append(diagnostics, errorDiagnostic("network-unresolved", "$.networking.egress", "target context has no egress controls"))
	}

	if requiredDefaultDeny && !boolAt(egress, "defaultDeny") {
		diagnostics = append(diagnostics, errorDiagnostic("network-unresolved", "$.networking.egress.default", "target context cannot enforce default-deny egress"))
	}

	allowed := stringSet(stringListAt(egress, "allow"))
	for _, destination := range requiredDestinations {
		if !allowed[destination] {
			diagnostics = append(diagnostics, errorDiagnostic("network-unresolved", "$.networking.egress.allow", "target context does not allow egress destination: "+destination))
		}
	}

	return diagnostics
}

func validateSecurity(root, target map[string]any) []diagnostic {
	var diagnostics []diagnostic

	requiredSandbox := stringAt(root, "security", "defaultSandbox")
	if requiredSandbox != "" && !stringSet(stringListAt(target, "security", "sandbox", "levels"))[requiredSandbox] {
		diagnostics = append(diagnostics, errorDiagnostic("security-policy-unenforceable", "$.security.defaultSandbox", "target context cannot enforce sandbox level: "+requiredSandbox))
	}

	requiredToolDefault := stringAt(root, "security", "toolPolicy", "default")
	if requiredToolDefault != "" && !stringSet(stringListAt(target, "security", "toolPolicy", "defaults"))[requiredToolDefault] {
		diagnostics = append(diagnostics, errorDiagnostic("security-policy-unenforceable", "$.security.toolPolicy.default", "target context cannot enforce tool policy default: "+requiredToolDefault))
	}

	return diagnostics
}

func validateSupplyChain(root, target map[string]any) []diagnostic {
	var diagnostics []diagnostic
	images := mapAt(root, "supplyChain", "images")
	if images == nil {
		return diagnostics
	}

	signature := mapAt(images, "signature")
	if boolAt(signature, "required") {
		targetSignatures := mapAt(target, "supplyChain", "signatures")
		if !boolAt(targetSignatures, "available") {
			diagnostics = append(diagnostics, errorDiagnostic("supply-chain-unverified", "$.supplyChain.images.signature", "target context cannot verify required image signatures"))
		} else if verifier := stringAt(signature, "verifier"); verifier != "" && !stringSet(stringListAt(targetSignatures, "verifiers"))[verifier] {
			diagnostics = append(diagnostics, errorDiagnostic("supply-chain-unverified", "$.supplyChain.images.signature.verifier", "target context does not support signature verifier: "+verifier))
		}
	}

	sbom := mapAt(images, "sbom")
	if boolAt(sbom, "required") {
		targetSBOM := mapAt(target, "supplyChain", "sbom")
		if !boolAt(targetSBOM, "available") {
			diagnostics = append(diagnostics, errorDiagnostic("supply-chain-unverified", "$.supplyChain.images.sbom", "target context cannot provide required SBOMs"))
		} else {
			supportedFormats := stringSet(stringListAt(targetSBOM, "formats"))
			for _, format := range stringListAt(sbom, "formats") {
				if !supportedFormats[format] {
					diagnostics = append(diagnostics, errorDiagnostic("supply-chain-unverified", "$.supplyChain.images.sbom.formats", "target context does not support SBOM format: "+format))
				}
			}
		}
	}

	provenance := mapAt(images, "provenance")
	if boolAt(provenance, "required") {
		targetProvenance := mapAt(target, "supplyChain", "provenance")
		if !boolAt(targetProvenance, "available") {
			diagnostics = append(diagnostics, errorDiagnostic("supply-chain-unverified", "$.supplyChain.images.provenance", "target context cannot provide required provenance"))
		}
	}

	return diagnostics
}

type namedRequirement struct {
	Name string
	For  []string
}

func requiredCapabilities(root map[string]any) []namedRequirement {
	return namedRequirements(listAt(root, "capabilities", "required"))
}

func requiredSecrets(root map[string]any) []namedRequirement {
	return namedRequirements(listAt(root, "secrets", "required"))
}

func namedRequirements(values []any) []namedRequirement {
	var requirements []namedRequirement
	for _, value := range values {
		switch typed := value.(type) {
		case string:
			requirements = append(requirements, namedRequirement{Name: typed})
		case map[string]any:
			requirements = append(requirements, namedRequirement{
				Name: stringAt(typed, "name"),
				For:  stringsFromValue(typed["for"]),
			})
		}
	}
	return requirements
}

func missingAuditEvents(root map[string]any) []string {
	required := stringSet(stringListAt(root, "observability", "auditEvents", "required"))
	var recommended []string

	if isProduction(root) {
		recommended = append(recommended, "deployment_planned")
	}
	if len(requiredSecrets(root)) > 0 {
		recommended = append(recommended, "secret_resolved")
	}

	hasHumanApproval := false
	hasPolicyApproval := false
	for _, approvalEntry := range listAt(root, "approvals", "required") {
		approval, ok := approvalEntry.(map[string]any)
		if !ok {
			continue
		}
		switch stringAt(approval, "mode") {
		case "human":
			hasHumanApproval = true
		case "policy":
			hasPolicyApproval = true
		case "policy-and-human":
			hasHumanApproval = true
			hasPolicyApproval = true
		}
	}
	if hasHumanApproval {
		recommended = append(recommended, "approval_requested", "approval_granted", "approval_denied")
	}
	if hasPolicyApproval {
		recommended = append(recommended, "policy_decision_recorded")
	}
	if stringAt(root, "security", "toolPolicy", "default") == "deny" || len(stringListAt(root, "security", "toolPolicy", "deny")) > 0 {
		recommended = append(recommended, "tool_call_denied")
	}

	var missing []string
	for _, event := range uniqueStrings(recommended) {
		if !required[event] {
			missing = append(missing, event)
		}
	}
	sort.Strings(missing)
	return missing
}

func missingThreatModelCoverage(root map[string]any) []string {
	if !isProduction(root) {
		return nil
	}

	var missing []string
	if len(listAt(root, "security", "trustBoundaries")) == 0 {
		missing = append(missing, "$.security.trustBoundaries")
	}

	threatModel := mapAt(root, "security", "threatModel")
	if threatModel == nil {
		missing = append(missing, "$.security.threatModel")
		return missing
	}
	if len(listAt(threatModel, "assets")) == 0 {
		missing = append(missing, "$.security.threatModel.assets")
	}
	if len(listAt(threatModel, "actors")) == 0 {
		missing = append(missing, "$.security.threatModel.actors")
	}
	if len(listAt(threatModel, "threats")) == 0 {
		missing = append(missing, "$.security.threatModel.threats")
	}
	if len(listAt(threatModel, "mitigations")) == 0 {
		missing = append(missing, "$.security.threatModel.mitigations")
	}
	review := mapAt(threatModel, "review")
	if stringAt(review, "status") == "" || stringAt(review, "reviewedBy") == "" {
		missing = append(missing, "$.security.threatModel.review")
	}
	return missing
}

func isProduction(root map[string]any) bool {
	return stringAt(root, "metadata", "labels", "tier") == "production"
}

func errorDiagnostic(category, path, message string) diagnostic {
	return diagnostic{Category: category, Severity: "error", Path: path, Message: message}
}

func warningDiagnostic(category, path, message string) diagnostic {
	return diagnostic{Category: category, Severity: "warning", Path: path, Message: message}
}

var knownRootFields = map[string]bool{
	"apiVersion":    true,
	"kind":          true,
	"metadata":      true,
	"profiles":      true,
	"runtime":       true,
	"capabilities":  true,
	"secrets":       true,
	"security":      true,
	"supplyChain":   true,
	"approvals":     true,
	"observability": true,
	"networking":    true,
	"reliability":   true,
	"extensions":    true,
}

var standardAuditEvents = map[string]bool{
	"deployment_planned":        true,
	"deployment_applied":        true,
	"deployment_failed":         true,
	"deployment_rolled_back":    true,
	"approval_requested":        true,
	"approval_granted":          true,
	"approval_denied":           true,
	"approval_expired":          true,
	"policy_evaluated":          true,
	"policy_decision_recorded":  true,
	"secret_resolved":           true,
	"secret_rotation_due":       true,
	"secret_rotation_completed": true,
	"secret_rotation_failed":    true,
	"tool_call_requested":       true,
	"tool_call_allowed":         true,
	"tool_call_denied":          true,
	"tool_call_executed":        true,
	"action_executed":           true,
	"egress_allowed":            true,
	"egress_denied":             true,
	"state_checkpoint_written":  true,
	"state_restore_started":     true,
	"state_restore_completed":   true,
	"state_restore_failed":      true,
}

func isAuditEventName(value string) bool {
	if standardAuditEvents[value] {
		return true
	}
	parts := strings.Split(value, "/")
	return len(parts) == 2 && parts[0] != "" && parts[1] != ""
}

func lookup(root map[string]any, keys ...string) any {
	var current any = root
	for _, key := range keys {
		mapping, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = mapping[key]
	}
	return current
}

func mapAt(root map[string]any, keys ...string) map[string]any {
	value := lookup(root, keys...)
	if mapping, ok := value.(map[string]any); ok {
		return mapping
	}
	return nil
}

func listAt(root map[string]any, keys ...string) []any {
	value := lookup(root, keys...)
	if list, ok := value.([]any); ok {
		return list
	}
	return nil
}

func stringAt(root map[string]any, keys ...string) string {
	if root == nil {
		return ""
	}
	value := lookup(root, keys...)
	if text, ok := value.(string); ok {
		return text
	}
	return ""
}

func boolAt(root map[string]any, keys ...string) bool {
	if root == nil {
		return false
	}
	value := lookup(root, keys...)
	if boolean, ok := value.(bool); ok {
		return boolean
	}
	return false
}

func stringListAt(root map[string]any, keys ...string) []string {
	if root == nil {
		return nil
	}
	return stringsFromValue(lookup(root, keys...))
}

func stringsFromValue(value any) []string {
	switch typed := value.(type) {
	case nil:
		return nil
	case string:
		return []string{typed}
	case []any:
		var out []string
		for _, entry := range typed {
			if text, ok := entry.(string); ok {
				out = append(out, text)
			}
		}
		return out
	default:
		return nil
	}
}

func stringSet(values []string) map[string]bool {
	out := map[string]bool{}
	for _, value := range values {
		out[value] = true
	}
	return out
}

func keySet(mapping map[string]any) map[string]bool {
	out := map[string]bool{}
	for key := range mapping {
		out[key] = true
	}
	return out
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, value := range values {
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		out = append(out, value)
	}
	return out
}

type yamlLine struct {
	indent int
	text   string
	number int
}

func parseYAMLFile(path string) (any, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return nil, err
	}
	return parseYAML(string(data), path)
}

func parseYAML(input, path string) (any, error) {
	lines, err := tokenizeYAML(input, path)
	if err != nil {
		return nil, err
	}
	if len(lines) == 0 {
		return map[string]any{}, nil
	}
	index := 0
	value, err := parseYAMLNode(lines, &index, lines[0].indent)
	if err != nil {
		return nil, err
	}
	if index != len(lines) {
		return nil, fmt.Errorf("%s:%d: unexpected trailing content", path, lines[index].number)
	}
	return value, nil
}

func tokenizeYAML(input, path string) ([]yamlLine, error) {
	var lines []yamlLine
	for index, rawLine := range strings.Split(input, "\n") {
		line := strings.TrimRight(rawLine, " \r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		if strings.Contains(line, "\t") {
			return nil, fmt.Errorf("%s:%d: tabs are not supported by this fixture parser", path, index+1)
		}
		indent := len(line) - len(strings.TrimLeft(line, " "))
		lines = append(lines, yamlLine{indent: indent, text: strings.TrimSpace(line), number: index + 1})
	}
	return lines, nil
}

func parseYAMLNode(lines []yamlLine, index *int, indent int) (any, error) {
	if *index >= len(lines) {
		return nil, nil
	}
	if lines[*index].indent != indent {
		return nil, fmt.Errorf("line %d: expected indent %d, got %d", lines[*index].number, indent, lines[*index].indent)
	}
	if strings.HasPrefix(lines[*index].text, "- ") {
		return parseYAMLSequence(lines, index, indent)
	}
	return parseYAMLMapping(lines, index, indent)
}

func parseYAMLMapping(lines []yamlLine, index *int, indent int) (map[string]any, error) {
	mapping := map[string]any{}

	for *index < len(lines) {
		line := lines[*index]
		if line.indent < indent {
			break
		}
		if line.indent > indent {
			return nil, fmt.Errorf("line %d: unexpected indent %d", line.number, line.indent)
		}
		if strings.HasPrefix(line.text, "- ") {
			break
		}

		key, rawValue, ok := splitYAMLMapping(line.text)
		if !ok {
			return nil, fmt.Errorf("line %d: expected mapping entry", line.number)
		}
		(*index)++

		value, err := parseYAMLValue(rawValue, lines, index, indent)
		if err != nil {
			return nil, err
		}
		mapping[key] = value
	}

	return mapping, nil
}

func parseYAMLSequence(lines []yamlLine, index *int, indent int) ([]any, error) {
	var sequence []any

	for *index < len(lines) {
		line := lines[*index]
		if line.indent < indent {
			break
		}
		if line.indent > indent {
			return nil, fmt.Errorf("line %d: unexpected sequence indent %d", line.number, line.indent)
		}
		if !strings.HasPrefix(line.text, "- ") {
			break
		}

		rest := strings.TrimSpace(strings.TrimPrefix(line.text, "- "))
		(*index)++
		if rest == "" {
			value, err := parseYAMLChild(lines, index, indent)
			if err != nil {
				return nil, err
			}
			sequence = append(sequence, value)
			continue
		}

		key, rawValue, ok := splitYAMLMapping(rest)
		if !ok {
			sequence = append(sequence, parseYAMLScalar(rest))
			continue
		}

		item := map[string]any{}
		value, err := parseYAMLValue(rawValue, lines, index, indent)
		if err != nil {
			return nil, err
		}
		item[key] = value

		if *index < len(lines) && lines[*index].indent > indent {
			more, err := parseYAMLMapping(lines, index, lines[*index].indent)
			if err != nil {
				return nil, err
			}
			for moreKey, moreValue := range more {
				item[moreKey] = moreValue
			}
		}

		sequence = append(sequence, item)
	}

	return sequence, nil
}

func parseYAMLValue(rawValue string, lines []yamlLine, index *int, parentIndent int) (any, error) {
	rawValue = strings.TrimSpace(rawValue)
	if rawValue != "" {
		return parseYAMLScalar(rawValue), nil
	}
	return parseYAMLChild(lines, index, parentIndent)
}

func parseYAMLChild(lines []yamlLine, index *int, parentIndent int) (any, error) {
	if *index >= len(lines) || lines[*index].indent <= parentIndent {
		return map[string]any{}, nil
	}
	return parseYAMLNode(lines, index, lines[*index].indent)
}

func splitYAMLMapping(text string) (string, string, bool) {
	for index := 0; index < len(text); index++ {
		if text[index] != ':' {
			continue
		}
		if index+1 < len(text) && text[index+1] != ' ' {
			continue
		}
		key := strings.TrimSpace(text[:index])
		if key == "" {
			return "", "", false
		}
		value := ""
		if index+1 < len(text) {
			value = strings.TrimSpace(text[index+1:])
		}
		return key, value, true
	}
	return "", "", false
}

func parseYAMLScalar(value string) any {
	switch value {
	case "[]":
		return []any{}
	case "{}":
		return map[string]any{}
	case "true":
		return true
	case "false":
		return false
	}

	if len(value) >= 2 {
		if (value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'') {
			return value[1 : len(value)-1]
		}
	}

	if number, err := strconv.Atoi(value); err == nil {
		return number
	}
	return value
}
