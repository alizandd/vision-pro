# CLAUDE.md - AI Assistant Guide for vision-pro

**Last Updated**: 2026-01-06
**Repository**: vision-pro
**Status**: New/Empty Repository

---

## Overview

This repository is currently empty and appears to be a new project. This document serves as a guide for AI assistants (like Claude) working on this codebase. It will be updated as the project evolves.

### Repository Information
- **Repository Name**: vision-pro
- **Remote URL**: http://local_proxy@127.0.0.1:30432/git/alizandd/vision-pro
- **Current Branch**: claude/claude-md-mk27b8klqx5sqaip-INL2T
- **Repository Status**: Empty (no commits, no source files)

---

## Project Structure

_This section will be updated as the project structure is established._

```
vision-pro/
├── .git/                 # Git repository metadata
└── CLAUDE.md            # This file - AI assistant guide
```

### Expected Structure (To Be Confirmed)

Based on the repository name "vision-pro", this project may involve:
- Vision processing/computer vision
- Apple Vision Pro development
- Virtual/Augmented Reality applications
- 3D graphics or spatial computing

The project structure will likely include:
```
vision-pro/
├── src/                 # Source code
├── tests/               # Test files
├── docs/                # Documentation
├── config/              # Configuration files
├── package.json         # Dependencies (if Node.js/TypeScript)
├── requirements.txt     # Dependencies (if Python)
└── README.md           # Project documentation
```

---

## Technology Stack

_To be determined. Watch for:_
- Programming language(s)
- Frameworks and libraries
- Build tools
- Testing frameworks
- Development dependencies

---

## Development Workflow

### Branch Strategy

**Important**: This repository uses a specific branch naming convention:
- Feature branches must start with `claude/`
- Current working branch: `claude/claude-md-mk27b8klqx5sqaip-INL2T`
- All development work should be committed to the designated Claude branch
- Push to remote using: `git push -u origin <branch-name>`

### Git Operations

**Pushing Changes:**
```bash
git push -u origin claude/claude-md-mk27b8klqx5sqaip-INL2T
```

**Critical Requirements:**
- Branch names MUST start with 'claude/' and match the session ID
- Pushing to wrong branch will fail with 403 error
- If push fails due to network errors, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s)

**Fetching/Pulling:**
```bash
git fetch origin <branch-name>
git pull origin <branch-name>
```

### Commit Message Convention

_To be established. Common patterns:_
- Use imperative mood ("Add feature" not "Added feature")
- First line: brief summary (50 chars or less)
- Blank line, then detailed description if needed
- Reference issue numbers when applicable

Example:
```
Add initial project structure

- Set up directory layout
- Configure build tools
- Add basic documentation
```

---

## Code Conventions

_This section will be populated as coding standards are established._

### General Principles
- Write clean, readable, and maintainable code
- Follow the Single Responsibility Principle
- Keep functions small and focused
- Use meaningful variable and function names
- Comment complex logic, but prefer self-documenting code

### Naming Conventions
_To be defined based on primary language_

### Code Style
_To be defined. May include:_
- Indentation (spaces vs tabs)
- Line length limits
- Import/require ordering
- File organization

---

## Testing Strategy

_To be established. May include:_

### Test Types
- Unit tests
- Integration tests
- End-to-end tests
- Performance tests

### Running Tests
```bash
# Commands to be added when test framework is set up
```

### Coverage Requirements
_Define minimum code coverage expectations_

---

## Build and Deployment

### Local Development Setup
```bash
# Setup commands to be added
# Example:
# npm install
# pip install -r requirements.txt
```

### Building the Project
```bash
# Build commands to be added
```

### Running Locally
```bash
# Run commands to be added
```

### Deployment
_Deployment process to be documented_

---

## Dependencies Management

### Adding Dependencies
_Guidelines for adding new dependencies:_
- Evaluate necessity and alternatives
- Check license compatibility
- Consider bundle size impact
- Review security advisories
- Document why the dependency is needed

### Updating Dependencies
- Regular security updates
- Test thoroughly after updates
- Check for breaking changes

---

## File Organization

### Source Code
_Organize by feature, module, or layer depending on project type_

### Configuration Files
- Keep configuration separate from code
- Use environment variables for sensitive data
- Document all configuration options

### Documentation
- Keep docs close to the code they document
- Update docs when code changes
- Include examples where helpful

---

## AI Assistant Guidelines

### Best Practices for Claude

1. **Always Read Before Writing**
   - Never modify files without reading them first
   - Understand existing patterns and conventions
   - Look for similar existing implementations

2. **Minimal Changes**
   - Only make changes that are directly requested
   - Avoid over-engineering or adding unrequested features
   - Don't refactor unrelated code unless asked

3. **Security First**
   - Watch for common vulnerabilities (XSS, SQL injection, command injection)
   - Validate input at system boundaries
   - Don't expose sensitive information

4. **Use Appropriate Tools**
   - Use Read/Edit/Write for file operations (not bash cat/sed)
   - Use Grep for code search
   - Use Glob for file pattern matching
   - Use Task tool for complex exploration

5. **Communication**
   - Provide clear explanations of changes
   - Reference specific files and line numbers
   - Ask for clarification when requirements are unclear

6. **Testing**
   - Run tests after making changes
   - Add tests for new functionality
   - Fix any breaking tests before completing tasks

### Common Tasks

#### Adding a New Feature
1. Understand the requirements
2. Explore existing code for patterns
3. Plan the implementation
4. Write the code following existing conventions
5. Add tests
6. Update documentation
7. Commit with clear message

#### Fixing a Bug
1. Reproduce the issue
2. Identify root cause
3. Fix the minimum necessary code
4. Add test to prevent regression
5. Verify fix works
6. Commit

#### Refactoring
1. Ensure tests exist and pass
2. Make incremental changes
3. Run tests after each change
4. Keep commits atomic
5. Update documentation if needed

---

## Project-Specific Knowledge

_This section will contain domain-specific information about the project._

### Architecture Decisions
_Document key architectural choices and rationale_

### Third-Party Integrations
_List and document external services/APIs used_

### Performance Considerations
_Document performance requirements and optimization strategies_

### Known Issues and Limitations
_Track known issues and technical debt_

---

## Resources and References

### Documentation
- _Links to external documentation_
- _Links to API references_
- _Links to tutorials or guides_

### Tools
- _Development tools used_
- _Debugging tools_
- _Monitoring and analytics_

### Community
- _Issue tracker_
- _Discussion forums_
- _Contributing guidelines_

---

## Changelog

### 2026-01-06
- Initial CLAUDE.md created
- Repository initialized but empty
- Established branch naming conventions and git workflow

---

## Notes for Future Updates

When updating this document as the project develops:

1. **Add actual project structure** once files are created
2. **Document the technology stack** when dependencies are added
3. **Define code conventions** based on language and framework chosen
4. **Add build/test commands** when build system is set up
5. **Document APIs and key modules** as they are developed
6. **Update examples** with real code from the project
7. **Add troubleshooting section** for common issues
8. **Include performance benchmarks** if relevant
9. **Document environment setup** with actual requirements
10. **Add links to related resources** as they become available

---

## Quick Reference

### Essential Commands
```bash
# Git operations
git status
git add .
git commit -m "Message"
git push -u origin claude/claude-md-mk27b8klqx5sqaip-INL2T

# To be added:
# - Build commands
# - Test commands
# - Run commands
```

### Important Files
- `CLAUDE.md` - This file, AI assistant guide
- _Other important files to be listed as project develops_

### Contact
- Repository Owner: alizandd
- _Add other contact information as needed_

---

**Remember**: This is a living document. Update it as the project evolves to keep it useful and accurate.
