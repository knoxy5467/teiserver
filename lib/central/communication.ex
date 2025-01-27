defmodule Central.Communication do
  @moduledoc """
  The Communication context.
  """

  import Ecto.Query, warn: false
  alias Central.Helpers.QueryHelpers
  alias Central.Repo

  alias Central.Communication.{Notification, NotificationLib}

  @doc """
  Returns the list of notifications.

  ## Examples

      iex> list_notifications()
      [%Notification{}, ...]

  """
  def list_notifications(args \\ []) do
    NotificationLib.get_notifications()
    |> NotificationLib.search(args[:search])
    |> NotificationLib.preload(args[:joins])
    |> NotificationLib.order(args[:order])
    |> Repo.all()
  end

  def list_user_notifications(user_id) do
    list_notifications(
      search: [
        user_id: user_id
      ]
    )
  end

  def list_user_notifications(user_id, :unread) do
    list_notifications(
      search: [
        user_id: user_id,
        read: false,
        expired: false,
        expires_after: Timex.local()
      ]
    )
  end

  def list_user_notifications(user_id, :expired) do
    list_notifications(
      search: [
        user_id: user_id,
        read: false,
        expired: true
      ]
    )
  end

  @doc """
  Gets a single notification.

  Raises `Ecto.NoResultsError` if the Notification does not exist.

  ## Examples

      iex> get_notification!(123)
      %Notification{}

      iex> get_notification!(456)
      ** (Ecto.NoResultsError)

  """
  def get_notification!(id, args \\ []) do
    NotificationLib.get_notifications()
    |> NotificationLib.search(%{id: id})
    |> NotificationLib.search(args[:search])
    |> NotificationLib.preload(args[:joins])
    |> Repo.one!()
  end

  @doc """
  Creates a notification.

  ## Examples

      iex> create_notification(%{field: value})
      {:ok, %Notification{}}

      iex> create_notification(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification.

  ## Examples

      iex> update_notification(notification, %{field: new_value})
      {:ok, %Notification{}}

      iex> update_notification(notification, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification(%Notification{} = notification, attrs) do
    notification
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Notification.

  ## Examples

      iex> delete_notification(notification)
      {:ok, %Notification{}}

      iex> delete_notification(notification)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification(%Notification{} = notification) do
    Repo.delete(notification)
  end

  def delete_all_notifications(user_id) do
    NotificationLib.get_notifications()
    |> NotificationLib.search(user_id: user_id)
    |> Repo.delete_all()
  end

  def delete_expired_notifications(user_id) do
    NotificationLib.get_notifications()
    |> NotificationLib.search(
      user_id: user_id,
      expired: true
    )
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking notification changes.

  ## Examples

      iex> change_notification(notification)
      %Ecto.Changeset{source: %Notification{}}

  """
  def change_notification(%Notification{} = notification) do
    Notification.changeset(notification, %{})
  end

  @doc """
  Sends out notifications to the user(s) listed in user_ids
  """

  def notify(user_ids, data, expires, prevent_duplicates) when is_integer(expires) do
    notify(
      user_ids,
      data,
      Timex.shift(Timex.now(), days: expires),
      prevent_duplicates
    )
  end

  def notify(user_ids, data, expires, prevent_duplicates) when is_integer(user_ids) do
    notify([user_ids], data, expires, prevent_duplicates)
  end

  def notify(user_ids, data, expires, prevent_duplicates) do
    user_skips =
      if prevent_duplicates do
        query =
          from notifications in Notification,
            where: notifications.user_id in ^user_ids,
            where: notifications.read == false,
            where: notifications.expires > ^Timex.now(),
            where: notifications.title == ^data.title,
            where: notifications.body == ^data.body,
            select: notifications.user_id,
            distinct: true

        Repo.all(query)
      else
        []
      end

    user_ids
    |> Enum.filter(fn u -> not Enum.member?(user_skips, u) end)
    |> Enum.map(fn uid ->
      %Notification{}
      |> Notification.new_changeset(%{
        "user_id" => uid,
        "title" => data.title,
        "body" => data.body,
        "icon" => data.icon,
        "colour" => data.colour,
        "redirect" => data.redirect,
        "expires" => expires
      })
      |> Repo.insert!()
    end)
    |> Enum.map(fn data ->
      CentralWeb.Endpoint.broadcast(
        "communication_notification:#{data.user_id}",
        "new communication notifictation",
        %{
          id: data.id,
          title: data.title,
          body: data.body,
          icon: data.icon,
          colour: data.colour,
          redirect: data.redirect,
          expires: expires
        }
      )

      data
    end)
  end

  def notification_url(notification) do
    url = notification.redirect

    cond do
      String.contains?(url, "?") ->
        String.replace(url, "?", "?anid=#{notification.id}")

      String.contains?(url, "#") ->
        String.replace(url, "#", "?anid=#{notification.id}#")

      true ->
        url <> "?anid=#{notification.id}"
    end
  end

  def mark_all_notification_as_read(user_id) do
    query =
      from n in Notification,
        where: n.user_id == ^user_id,
        update: [set: [read: true]]

    Repo.update_all(query, [])
  end

  def mark_notification_as_read(user_id, notification_id) do
    query =
      from n in Notification,
        where: n.id == ^notification_id,
        where: n.user_id == ^user_id,
        update: [set: [read: true]]

    Repo.update_all(query, [])
  end

  # Blog stuff
  alias Central.Communication.{BlogFile, BlogFileLib}

  @doc """
  Returns the list of blog_files.

  ## Examples

      iex> list_blog_files()
      [%BlogFile{}, ...]

  """
  def list_blog_files(args \\ []) do
    BlogFileLib.get_blog_files()
    |> BlogFileLib.search(args[:search])
    |> BlogFileLib.preload(args[:joins])
    |> BlogFileLib.order_by(args[:order_by])
    |> Repo.all()
  end

  @doc """
  Gets a single blog_file.

  Raises `Ecto.NoResultsError` if the BlogFile does not exist.

  ## Examples

      iex> get_blog_file!(123)
      %BlogFile{}

      iex> get_blog_file!(456)
      ** (Ecto.NoResultsError)

  """
  def get_blog_file!(id, args \\ []) do
    BlogFileLib.get_blog_files()
    |> BlogFileLib.search(%{id: id})
    |> BlogFileLib.search(args[:search])
    |> BlogFileLib.preload(args[:joins])
    |> Repo.one!()
  end

  def get_blog_file_by_url!(url, _args \\ []) do
    BlogFileLib.get_blog_files()
    |> BlogFileLib.search(%{url: url})
    |> Repo.one!()
  end

  @doc """
  Creates a blog_file.

  ## Examples

      iex> create_blog_file(%{field: value})
      {:ok, %BlogFile{}}

      iex> create_blog_file(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_blog_file(attrs \\ %{}) do
    %BlogFile{}
    |> BlogFile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a blog_file.

  ## Examples

      iex> update_blog_file(blog_file, %{field: new_value})
      {:ok, %BlogFile{}}

      iex> update_blog_file(blog_file, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_blog_file(%BlogFile{} = blog_file, attrs) do
    blog_file
    |> BlogFile.changeset(attrs)
    |> Repo.update()
  end

  def update_blog_file_upload(%BlogFile{} = blog_file, file_path, file_ext, file_size) do
    blog_file
    |> BlogFile.file_upload_changeset(file_path, file_ext, file_size)
    |> Repo.update()
  end

  @doc """
  Deletes a BlogFile.

  ## Examples

      iex> delete_blog_file(blog_file)
      {:ok, %BlogFile{}}

      iex> delete_blog_file(blog_file)
      {:error, %Ecto.Changeset{}}

  """
  def delete_blog_file(%BlogFile{} = blog_file) do
    Repo.delete(blog_file)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking blog_file changes.

  ## Examples

      iex> change_blog_file(blog_file)
      %Ecto.Changeset{source: %BlogFile{}}

  """
  def change_blog_file(%BlogFile{} = blog_file) do
    BlogFile.changeset(blog_file, %{})
  end

  alias Central.Communication.{Category, CategoryLib}

  @doc """
  Returns the list of categories.

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

  """
  def list_categories(args \\ []) do
    CategoryLib.get_categories()
    |> CategoryLib.search(args[:search])
    |> CategoryLib.preload(args[:joins])
    |> CategoryLib.order_by(args[:order_by])
    |> Repo.all()
  end

  @doc """
  Gets a single category.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(123)
      %Category{}

      iex> get_category!(456)
      ** (Ecto.NoResultsError)

  """
  def get_category(id, args \\ []) do
    CategoryLib.get_categories()
    |> CategoryLib.search(%{id: id})
    |> CategoryLib.search(args[:search])
    |> CategoryLib.preload(args[:joins])
    |> Repo.one()
  end

  def get_category!(id, args \\ []) do
    CategoryLib.get_categories()
    |> CategoryLib.search(%{id: id})
    |> CategoryLib.search(args[:search])
    |> CategoryLib.preload(args[:joins])
    |> Repo.one!()
  end

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(%{field: value})
      {:ok, %Category{}}

      iex> create_category(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Category.

  ## Examples

      iex> delete_category(category)
      {:ok, %Category{}}

      iex> delete_category(category)
      {:error, %Ecto.Changeset{}}

  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(category)
      %Ecto.Changeset{source: %Category{}}

  """
  def change_category(%Category{} = category) do
    Category.changeset(category, %{})
  end

  alias Central.Communication.Comment
  alias Central.Communication.CommentLib

  @doc """
  Returns the list of comments.

  ## Examples

      iex> list_comments()
      [%Comment{}, ...]

  """
  def list_comments(args \\ []) do
    CommentLib.get_comments()
    |> CommentLib.search(args[:search])
    |> CommentLib.preload(args[:joins])
    |> CommentLib.order_by(args[:order_by])
    |> Repo.all()
  end

  @doc """
  Gets a single comment.

  Raises `Ecto.NoResultsError` if the Comment does not exist.

  ## Examples

      iex> get_comment!(123)
      %Comment{}

      iex> get_comment!(456)
      ** (Ecto.NoResultsError)

  """
  def get_comment!(id, args \\ []) do
    CommentLib.get_comments()
    |> CommentLib.search(%{id: id})
    |> CommentLib.search(args[:search])
    |> CommentLib.preload(args[:joins])
    |> Repo.one!()
  end

  @doc """
  Creates a comment.

  ## Examples

      iex> create_comment(%{field: value})
      {:ok, %Comment{}}

      iex> create_comment(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_comment(attrs \\ %{}) do
    %Comment{}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a comment.

  ## Examples

      iex> update_comment(comment, %{field: new_value})
      {:ok, %Comment{}}

      iex> update_comment(comment, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_comment(%Comment{} = comment, attrs) do
    comment
    |> Comment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Comment.

  ## Examples

      iex> delete_comment(comment)
      {:ok, %Comment{}}

      iex> delete_comment(comment)
      {:error, %Ecto.Changeset{}}

  """
  def delete_comment(%Comment{} = comment) do
    Repo.delete(comment)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment changes.

  ## Examples

      iex> change_comment(comment)
      %Ecto.Changeset{source: %Comment{}}

  """
  def change_comment(%Comment{} = comment) do
    Comment.changeset(comment, %{})
  end

  alias Central.Communication.{Post, PostLib}

  @doc """
  Returns the list of posts.

  ## Examples

      iex> list_posts()
      [%Post{}, ...]

  """
  def list_posts(args \\ []) do
    PostLib.get_posts()
    |> PostLib.search(args[:search])
    |> PostLib.preload(args[:joins])
    |> PostLib.order_by(args[:order_by])
    |> QueryHelpers.limit_query(args[:limit] || 50)
    |> Repo.all()
  end

  def get_post(id, args \\ []) do
    PostLib.get_posts()
    |> PostLib.search(%{id: id})
    |> PostLib.search(args[:search])
    |> PostLib.preload(args[:joins])
    |> Repo.one()
  end

  @doc """
  Gets a single post.

  Raises `Ecto.NoResultsError` if the Post does not exist.

  ## Examples

      iex> get_post!(123)
      %Post{}

      iex> get_post!(456)
      ** (Ecto.NoResultsError)

  """
  def get_post!(id, args \\ []) do
    PostLib.get_posts()
    |> PostLib.search(%{id: id})
    |> PostLib.search(args[:search])
    |> PostLib.preload(args[:joins])
    |> Repo.one!()
  end

  def get_post_by_url_slug(url_slug, args \\ []) do
    PostLib.get_posts()
    |> PostLib.search(%{url_slug: url_slug})
    |> PostLib.search(args[:search])
    |> PostLib.preload(args[:joins])
    |> Repo.one()
  end

  @doc """
  Creates a post.

  ## Examples

      iex> create_post(%{field: value})
      {:ok, %Post{}}

      iex> create_post(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a post.

  ## Examples

      iex> update_post(post, %{field: new_value})
      {:ok, %Post{}}

      iex> update_post(post, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Post.

  ## Examples

      iex> delete_post(post)
      {:ok, %Post{}}

      iex> delete_post(post)
      {:error, %Ecto.Changeset{}}

  """
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.

  ## Examples

      iex> change_post(post)
      %Ecto.Changeset{source: %Post{}}

  """
  def change_post(%Post{} = post) do
    Post.changeset(post, %{})
  end
end
