class CookbookCollaboratorAuthorizer < Authorizer::Base
  def create?
    record.cookbook.owner == user
  end

  def destroy?
    create? || record.user == user
  end
end
